----------------------------------------------------------------------------------
-- Engineer:    Vitor Mendes Camilo
--
-- Module Name: byte_stuffer - Behavioral
-- Description:
--
--   Per T.87: every 0xFF byte in the encoded bitstream must be followed by a
--   stuffed '0' bit so decoders can distinguish payload from markers (an FF
--   followed by a non-zero byte = marker).
--
--   Sits downstream of A11_2_bit_packer: input is a variable-length MSB-
--   aligned word (iWord, iWordValid, iValidLen). Output is a byte-aligned
--   stream up to OUT_BYTES_PER_CYCLE bytes per beat.
--
--   Three internal stages:
--
--     Stage 1 — bit packer:
--       Accumulates input bits MSB-first into a wide accumulator (no FF
--       logic). When >= FIFO_BYTES whole bytes are present, packs them
--       into a fixed-width FIFO word together with a byte-count and a
--       last_flag. Critical path: one barrel shift over IN_WIDTH bits.
--
--     Stage 2 — BRAM-backed sync FIFO:
--       olo_base_fifo_sync, decouples Stage 1 (bursts at LIMIT bits/cycle)
--       from Stage 3 (drains at OUT_BYTES_PER_CYCLE bytes/cycle post-stuff).
--       AlmFull -> oAlmostFull (backpressure to bit_packer / pipeline).
--
--     Stage 3 — FF stuffer + output emit:
--       Refills a holding register from FIFO pops. Each cycle consumes up
--       to OUT_BYTES_PER_CYCLE bytes through a serial FF-stuff chain (depth
--       = OUT_BYTES_PER_CYCLE). Stuffed bit stream goes into an output
--       bit accumulator; whole OUT_WIDTH-bit beats are emitted as soon as
--       available.
--
--   Flush protocol (iFlush, single-cycle pulse from upstream on the cycle
--   the bit_packer presents the image's last word):
--     - Stage 1 pads its sub-byte residue and tags the final FIFO write
--       with last_flag=1. If the accumulator was already empty, it emits
--       a count=0 sentinel with last_flag=1.
--     - Stage 3 latches the last_flag when it pops that word. Once the
--       holding register drains, it inserts a final stuff '0' if the last
--       payload byte was 0xFF, zero-pads the output accumulator to a byte
--       boundary, emits the remaining whole bytes, and pulses oFlushDone
--       on the final output beat (oFlushDone is sampled together with
--       oWordValid='1', matching jls_framer's iEOI contract).
--
-- Generics:
--   IN_WIDTH            : bit_packer worst-case word width (= LIMIT).
--   OUT_BYTES_PER_CYCLE : output bytes/cycle. Bounds the Stage 3 FF chain
--                         depth (4 bytes/cycle -> 4 levels).
--   BURST_DEPTH         : depth of the BRAM-backed FIFO (in wide words).
--
----------------------------------------------------------------------------------
use work.Common.all;

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

library openlogic_base;
use openlogic_base.olo_base_pkg_math.log2ceil;

entity byte_stuffer is
  generic (
    IN_WIDTH            : natural := CO_LIMIT_STD;
    OUT_BYTES_PER_CYCLE : natural := CO_BYTE_STUFFER_OUT_BYTES_PER_CYCLE;
    BURST_DEPTH         : natural := CO_BYTE_STUFFER_BURST_DEPTH
  );
  port (
    iClk        : in std_logic;
    iRst        : in std_logic;
    iStall      : in std_logic;
    iWord       : in std_logic_vector(IN_WIDTH - 1 downto 0);
    iWordValid  : in std_logic;
    iValidLen   : in unsigned(log2ceil(IN_WIDTH + 1) - 1 downto 0);
    iFlush      : in std_logic;
    oWord       : out std_logic_vector(OUT_BYTES_PER_CYCLE * 8 - 1 downto 0);
    oWordValid  : out std_logic;
    oValidBytes : out unsigned(log2ceil(OUT_BYTES_PER_CYCLE + 1) - 1 downto 0);
    oAlmostFull : out std_logic;
    oFlushDone  : out std_logic
  );
end entity byte_stuffer;

architecture Behavioral of byte_stuffer is

  constant OUT_WIDTH  : natural := OUT_BYTES_PER_CYCLE * 8;

  -- Stage 1 sizing (no FF stuff at this stage).
  constant FIFO_BYTES : natural := math_ceil_div(IN_WIDTH, 8);
  constant FIFO_BITS  : natural := FIFO_BYTES * 8;
  constant ACCUM_BITS : natural := IN_WIDTH + 7;
  constant COUNT_W    : natural := log2ceil(FIFO_BYTES + 1);

  -- FIFO entry layout (LSB-first):
  --   bits [0 .. COUNT_W-1]   : byte_count   (0 .. FIFO_BYTES)
  --   bit  [COUNT_W]          : last_flag
  --   bits [COUNT_W+1 .. .. ] : data (MSB-first packed bytes)
  constant LAST_POS   : natural := COUNT_W;
  constant DATA_LSB   : natural := COUNT_W + 1;
  constant FIFO_WIDTH : natural := FIFO_BITS + 1 + COUNT_W;

  function almfull_level(depth : natural) return natural is
  begin
    if depth >= 4 then
      return depth - 2;
    elsif depth >= 2 then
      return depth - 1;
    else
      return depth;
    end if;
  end function;
  constant ALM_FULL_LEVEL : natural := almfull_level(BURST_DEPTH);

  -- Stage 3 holding register: room for at least one full FIFO pop on top of
  -- any leftover bits from the previous consume. Bits are stored MSB-first
  -- (oldest emitted first) at the top of the buffer.
  constant HOLD_BYTES : natural := 2 * FIFO_BYTES;
  constant HOLD_BITS  : natural := HOLD_BYTES * 8;

  ----------------------------------------------------------------------------
  -- Stage 1 (bit packer) state
  ----------------------------------------------------------------------------
  signal sAccum        : std_logic_vector(ACCUM_BITS - 1 downto 0);
  signal sAccumBits    : unsigned(log2ceil(ACCUM_BITS + 1) - 1 downto 0);
  signal sFlushPending : std_logic;

  ----------------------------------------------------------------------------
  -- FIFO interface
  ----------------------------------------------------------------------------
  signal sFifoInData   : std_logic_vector(FIFO_WIDTH - 1 downto 0);
  signal sFifoInValid  : std_logic;
  signal sFifoInReady  : std_logic;
  signal sFifoOutData  : std_logic_vector(FIFO_WIDTH - 1 downto 0);
  signal sFifoOutValid : std_logic;
  signal sFifoOutReady : std_logic;
  signal sFifoAlmFull  : std_logic;

  ----------------------------------------------------------------------------
  -- Skid buffer between FIFO output and Stage 3 consume. Breaks the
  -- BRAM-DOADO -> Stage-3-LUT-cone combinational path (saves the BRAM Tco
  -- plus the long fanout net at the FIFO output from the Stage 3 critical
  -- path). Cost: +1 cycle FIFO read latency, hidden by FIFO depth.
  ----------------------------------------------------------------------------
  signal sStgData  : std_logic_vector(FIFO_WIDTH - 1 downto 0);
  signal sStgValid : std_logic;
  signal sStgTaken : std_logic;

  ----------------------------------------------------------------------------
  -- Stage 3 (FF stuffer + emit) state.
  --
  --   sHold/sHoldBits — bit-level holding buffer for input bits awaiting
  --                     emission. Bits are stored MSB-first at the top.
  --   sHoldLast       — sticky: latched when a FIFO word with last_flag=1
  --                     has been popped. Cleared after the final beat.
  --   sPrevFF         — '1' iff the last *output* byte (post-stuff) was
  --                     0xFF, meaning the next bit emitted to the output
  --                     stream must be the stuffed '0'.
  ----------------------------------------------------------------------------
  signal sHold      : std_logic_vector(HOLD_BITS - 1 downto 0);
  signal sHoldBits  : unsigned(log2ceil(HOLD_BITS + 1) - 1 downto 0);
  signal sHoldLast  : std_logic;
  signal sPrevFF    : std_logic;

  signal sOutWordReg   : std_logic_vector(OUT_WIDTH - 1 downto 0);
  signal sOutValidReg  : std_logic;
  signal sOutBytesReg  : unsigned(log2ceil(OUT_BYTES_PER_CYCLE + 1) - 1 downto 0);
  signal sFlushDone    : std_logic;

begin

  assert OUT_BYTES_PER_CYCLE >= 1
  report "byte_stuffer: OUT_BYTES_PER_CYCLE must be >= 1"
    severity failure;

  assert BURST_DEPTH >= 4
  report "byte_stuffer: BURST_DEPTH must be >= 4 (AlmFull slack)"
    severity failure;

  oWord       <= sOutWordReg;
  oWordValid  <= sOutValidReg;
  oValidBytes <= sOutBytesReg;
  oFlushDone  <= sFlushDone;
  oAlmostFull <= sFifoAlmFull;

  -------------------------------------------------------------------------------------------------------------------------
  -- STAGE 1: bit packer
  -- Append iWord's top iValidLen bits MSB-first into the accumulator; when
  -- >= FIFO_BYTES whole bytes are present (or any whole bytes under flush),
  -- pack them into a FIFO word with byte_count + last_flag.
  -------------------------------------------------------------------------------------------------------------------------
  stage1_proc : process (iClk)
    variable vAccum       : std_logic_vector(ACCUM_BITS - 1 downto 0);
    variable vBitsInt     : natural range 0 to ACCUM_BITS;
    variable vValidLenInt : natural;
    variable vFlushPend   : std_logic;
    variable vAccept      : boolean;
    variable vPadBits     : natural;
    variable vBytesReady  : natural;
    variable vEmitBytes   : natural;
    variable vLastFlag    : std_logic;
    variable vDataWord    : std_logic_vector(FIFO_BITS - 1 downto 0);
  begin
    if rising_edge(iClk) then

      if iRst = '1' then
        sAccum        <= (others => '0');
        sAccumBits    <= (others => '0');
        sFlushPending <= '0';
        sFifoInValid  <= '0';
        sFifoInData   <= (others => '0');

      else

        vAccum       := sAccum;
        vBitsInt     := to_integer(sAccumBits);
        vValidLenInt := to_integer(iValidLen);
        vFlushPend   := sFlushPending;
        vAccept      := (sFlushPending = '0') and (sFifoAlmFull = '0');

        sFifoInValid <= '0';

        -- Append input bits (MSB-first). No FF detect at this stage.
        if iWordValid = '1' and iStall = '0' and vAccept then
          for i in 0 to IN_WIDTH - 1 loop
            if i < vValidLenInt then
              vAccum(ACCUM_BITS - 1 - vBitsInt) := iWord(IN_WIDTH - 1 - i);
              vBitsInt                          := vBitsInt + 1;
            end if;
          end loop;
        end if;

        -- Flush entry: pad sub-byte residue to a byte boundary, mark pending.
        if iFlush = '1' and iStall = '0' and vAccept then
          if (vBitsInt mod 8) /= 0 then
            vPadBits := 8 - (vBitsInt mod 8);
            for j in 0 to 7 loop
              if j < vPadBits then
                vAccum(ACCUM_BITS - 1 - vBitsInt) := '0';
                vBitsInt                          := vBitsInt + 1;
              end if;
            end loop;
          end if;
          vFlushPend := '1';
        end if;

        -- Drain whole bytes to the FIFO. FIFO word carries variable count
        -- (1..FIFO_BYTES) so we can push any whole-byte residue; this keeps
        -- the accumulator bounded under sustained IN_WIDTH-bit input where
        -- a small residue would otherwise grow past FIFO_BITS.
        vBytesReady := vBitsInt / 8;
        if vBytesReady > FIFO_BYTES then
          vBytesReady := FIFO_BYTES;
        end if;

        if vBytesReady > 0 and sFifoAlmFull = '0' then

          vEmitBytes := vBytesReady;
          if vFlushPend = '1' and (vBitsInt - vEmitBytes * 8) = 0 then
            vLastFlag  := '1';
            vFlushPend := '0';
          else
            vLastFlag := '0';
          end if;

          vDataWord    := vAccum(ACCUM_BITS - 1 downto ACCUM_BITS - FIFO_BITS);
          sFifoInData  <= vDataWord
                          & vLastFlag
                          & std_logic_vector(to_unsigned(vEmitBytes, COUNT_W));
          sFifoInValid <= '1';

          vAccum   := std_logic_vector(shift_left(unsigned(vAccum), vEmitBytes * 8));
          vBitsInt := vBitsInt - vEmitBytes * 8;

        elsif vFlushPend = '1' and vBitsInt = 0 and sFifoAlmFull = '0' then
          -- Edge case: flush latched but accumulator already empty
          -- (no payload bytes for this image). Emit a count=0 sentinel.
          sFifoInData  <= (FIFO_WIDTH - 1 downto LAST_POS + 1 => '0')
                          & '1'
                          & std_logic_vector(to_unsigned(0, COUNT_W));
          sFifoInValid <= '1';
          vFlushPend   := '0';
        end if;

        sAccum        <= vAccum;
        sAccumBits    <= to_unsigned(vBitsInt, sAccumBits'length);
        sFlushPending <= vFlushPend;

        assert vBitsInt <= ACCUM_BITS
        report "byte_stuffer: stage 1 accumulator overflow"
          severity failure;

      end if;
    end if;
  end process stage1_proc;

  -------------------------------------------------------------------------------------------------------------------------
  -- STAGE 2: BRAM-backed sync FIFO
  -------------------------------------------------------------------------------------------------------------------------
  fifo_inst : entity openlogic_base.olo_base_fifo_sync
    generic map (
      Width_g        => FIFO_WIDTH,
      Depth_g        => BURST_DEPTH,
      AlmFullOn_g    => true,
      AlmFullLevel_g => ALM_FULL_LEVEL,
      RamStyle_g     => "block",
      RamBehavior_g  => "RBW"
    )
    port map (
      Clk       => iClk,
      Rst       => iRst,
      In_Data   => sFifoInData,
      In_Valid  => sFifoInValid,
      In_Ready  => sFifoInReady,
      Out_Data  => sFifoOutData,
      Out_Valid => sFifoOutValid,
      Out_Ready => sFifoOutReady,
      Full      => open,
      AlmFull   => sFifoAlmFull,
      Empty     => open,
      AlmEmpty  => open
    );

  -------------------------------------------------------------------------------------------------------------------------
  -- STAGE 3: FF stuffer + output emit
  --
  -- The stuffer operates on the unstuffed input bitstream and constructs
  -- output bytes one at a time. T.87 requires the stuff '0' bit to follow
  -- every *output* byte whose value is 0xFF, so FF detection is done on the
  -- constructed output byte (not the input byte) — after the first stuff,
  -- input and output byte alignments diverge.
  --
  -- Per output byte:
  --   * if prev_FF='1' (last output byte was FF), the next output byte's
  --     MSB is the stuffed '0'; consume 7 bits from the holding buffer to
  --     fill the remaining 7 bits.
  --   * else: consume 8 bits straight from the holding buffer.
  --   Then prev_FF := (byte == 0xFF).
  --
  -- Final-flush drain (vHoldLast='1' and vHoldBits=0):
  --   * if prev_FF='1': emit one final 0x00 byte (the stuff '0' + 7-bit pad).
  --   * pulse oFlushDone on the beat that carries the last data byte.
  -------------------------------------------------------------------------------------------------------------------------
  -- Stage 3 drains the skid buffer when it has data and the hold has room.
  sStgTaken     <= '1' when sStgValid = '1'
                       and sHoldBits <= to_unsigned(HOLD_BITS - FIFO_BITS, sHoldBits'length)
                       and iStall = '0'
                   else '0';
  -- Pop FIFO when the skid buffer is empty or being drained this cycle.
  sFifoOutReady <= '1' when sStgValid = '0' or sStgTaken = '1' else '0';

  skid_proc : process (iClk)
  begin
    if rising_edge(iClk) then
      if iRst = '1' then
        sStgValid <= '0';
        sStgData  <= (others => '0');
      else
        if sStgTaken = '1' then
          sStgValid <= '0';
        end if;
        if sFifoOutValid = '1' and sFifoOutReady = '1' then
          sStgData  <= sFifoOutData;
          sStgValid <= '1';
        end if;
      end if;
    end if;
  end process skid_proc;

  stage3_proc : process (iClk)
    variable vHold      : std_logic_vector(HOLD_BITS - 1 downto 0);
    variable vHoldBits  : natural range 0 to HOLD_BITS;
    variable vHoldLast  : std_logic;
    variable vPrevFF    : std_logic;

    variable vPopBytes  : natural range 0 to FIFO_BYTES;
    variable vPopLast   : std_logic;
    variable vPopData   : std_logic_vector(FIFO_BITS - 1 downto 0);

    variable vEmitBytes : natural range 0 to OUT_BYTES_PER_CYCLE;
    variable vEmitData  : std_logic_vector(OUT_WIDTH - 1 downto 0);
    variable vByte      : std_logic_vector(7 downto 0);
    variable vNeed      : natural range 0 to 8;
    variable vDone      : boolean;
    variable vFlushNow  : boolean;
  begin
    if rising_edge(iClk) then

      if iRst = '1' then
        sHold        <= (others => '0');
        sHoldBits    <= (others => '0');
        sHoldLast    <= '0';
        sPrevFF      <= '0';
        sOutWordReg  <= (others => '0');
        sOutValidReg <= '0';
        sOutBytesReg <= (others => '0');
        sFlushDone   <= '0';

      else

        vHold      := sHold;
        vHoldBits  := to_integer(sHoldBits);
        vHoldLast  := sHoldLast;
        vPrevFF    := sPrevFF;
        vEmitBytes := 0;
        vEmitData  := (others => '0');
        vDone      := false;
        vFlushNow  := false;
        sFlushDone <= '0';

        ----------------------------------------------------------------------
        -- (1) Refill: drain the skid buffer into the holding buffer.
        ----------------------------------------------------------------------
        if sStgTaken = '1' then
          vPopBytes := to_integer(unsigned(sStgData(COUNT_W - 1 downto 0)));
          vPopLast  := sStgData(LAST_POS);
          vPopData  := sStgData(FIFO_WIDTH - 1 downto DATA_LSB);
          for k in 0 to FIFO_BYTES - 1 loop
            if k < vPopBytes then
              vHold(HOLD_BITS - 1 - vHoldBits - k * 8
                    downto HOLD_BITS - vHoldBits - (k + 1) * 8)
                := vPopData(FIFO_BITS - 1 - k * 8
                            downto FIFO_BITS - (k + 1) * 8);
            end if;
          end loop;
          vHoldBits := vHoldBits + vPopBytes * 8;
          if vPopLast = '1' then
            vHoldLast := '1';
          end if;
        end if;

        ----------------------------------------------------------------------
        -- (2) Form up to OUT_BYTES_PER_CYCLE output bytes.
        ----------------------------------------------------------------------
        if iStall = '0' then
          for b in 0 to OUT_BYTES_PER_CYCLE - 1 loop
            if not vDone then

              if vPrevFF = '1' then
                vNeed := 7;
              else
                vNeed := 8;
              end if;

              if vHoldBits >= vNeed then
                -- Normal path: take vNeed bits from the top of the buffer.
                if vPrevFF = '1' then
                  vByte     := "0" & vHold(HOLD_BITS - 1 downto HOLD_BITS - 7);
                  vHold     := std_logic_vector(shift_left(unsigned(vHold), 7));
                  vHoldBits := vHoldBits - 7;
                else
                  vByte     := vHold(HOLD_BITS - 1 downto HOLD_BITS - 8);
                  vHold     := std_logic_vector(shift_left(unsigned(vHold), 8));
                  vHoldBits := vHoldBits - 8;
                end if;

                if vByte = x"FF" then
                  vPrevFF := '1';
                else
                  vPrevFF := '0';
                end if;

                vEmitData(OUT_WIDTH - 1 - vEmitBytes * 8
                          downto OUT_WIDTH - (vEmitBytes + 1) * 8) := vByte;
                vEmitBytes := vEmitBytes + 1;

              elsif vHoldLast = '1' then
                -- Final drain: not enough bits to form a whole byte and no
                -- more data will arrive. Build the last output byte from
                -- whatever's left, padded with zeros to a byte boundary.
                vByte := (others => '0');
                if vPrevFF = '1' then
                  -- bit 7 = stuff '0' (already in vByte), then up to 7 real
                  -- bits from the buffer, then zero pad to fill 8 bits.
                  if vHoldBits > 0 then
                    vByte(6 downto 7 - vHoldBits) :=
                      vHold(HOLD_BITS - 1 downto HOLD_BITS - vHoldBits);
                    vHold := std_logic_vector(
                               shift_left(unsigned(vHold), vHoldBits));
                    vHoldBits := 0;
                  end if;
                  vPrevFF := '0';
                  vEmitData(OUT_WIDTH - 1 - vEmitBytes * 8
                            downto OUT_WIDTH - (vEmitBytes + 1) * 8) := vByte;
                  vEmitBytes := vEmitBytes + 1;
                  vFlushNow  := true;
                  vHoldLast  := '0';
                  vDone      := true;
                elsif vHoldBits > 0 then
                  -- No prev_FF: real bits at the top, zero pad in the LSBs.
                  vByte(7 downto 8 - vHoldBits) :=
                    vHold(HOLD_BITS - 1 downto HOLD_BITS - vHoldBits);
                  vHold := std_logic_vector(
                             shift_left(unsigned(vHold), vHoldBits));
                  vHoldBits := 0;
                  if vByte = x"FF" then
                    vPrevFF := '1';  -- (cannot happen with zero pad in low bits)
                  end if;
                  vEmitData(OUT_WIDTH - 1 - vEmitBytes * 8
                            downto OUT_WIDTH - (vEmitBytes + 1) * 8) := vByte;
                  vEmitBytes := vEmitBytes + 1;
                  vFlushNow  := true;
                  vHoldLast  := '0';
                  vDone      := true;
                else
                  -- vHoldBits = 0, prev_FF = 0: nothing left to emit; the
                  -- flush_done attaches to a prior beat via the emit-side
                  -- guard. No byte produced this iteration.
                  vDone := true;
                end if;

              else
                -- Not enough bits to form another byte this cycle.
                vDone := true;
              end if;
            end if;
          end loop;
        end if;

        ----------------------------------------------------------------------
        -- (3) Emit. If after consume the buffer is fully drained and the
        --     last_flag is latched, this beat carries the last data byte —
        --     pulse oFlushDone with it (framer's iEOI is sampled together
        --     with iValid='1').
        ----------------------------------------------------------------------
        if vEmitBytes > 0 then
          sOutWordReg  <= vEmitData;
          sOutBytesReg <= to_unsigned(vEmitBytes, sOutBytesReg'length);
          sOutValidReg <= '1';

          if vFlushNow
             or (vHoldLast = '1' and vHoldBits = 0 and vPrevFF = '0') then
            sFlushDone <= '1';
            vHoldLast  := '0';
          end if;
        else
          sOutValidReg <= '0';
        end if;

        sHold     <= vHold;
        sHoldBits <= to_unsigned(vHoldBits, sHoldBits'length);
        sHoldLast <= vHoldLast;
        sPrevFF   <= vPrevFF;

      end if;
    end if;
  end process stage3_proc;

end architecture Behavioral;
