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
--       Refills a holding register from FIFO pops. Each cycle forms up to
--       OUT_BYTES_PER_CYCLE output bytes via:
--         (a) a parallel pre-compute of FF-equality flags over the 8 fixed
--             candidate byte windows that any of the 4 slots could ever
--             read from (offsets 0, 7, 8, 15, 16, 22, 23, 24); and
--         (b) a 4-step chain over the slots that resolves each slot's input
--             prev_FF and selects the correct candidate flag/bits via a
--             small mux. Each step is one mux + 1-LUT update, far shallower
--             than the original per-step variable-shift chain.
--       Holds shifts once at the end by the chain's total bit consumption
--       (28..32 bits per cycle when all 4 slots fire).
--
--       End-of-image partial-byte drain (sub-byte residue, or a pending
--       stuff bit with no follow-up data) is split into its own cycle via
--       sDrainPending: the padded byte is assembled, latched, and emitted
--       on the following beat. Adds at most 1 cycle of latency per image
--       boundary and keeps the pad-byte assembly off the critical path.
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

  constant OUT_WIDTH : natural := OUT_BYTES_PER_CYCLE * 8;

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
  -- Input shadow registers. Stage 1's wide variable shifter has a large
  -- cross-module routing footprint when driven directly by the upstream
  -- bit_packer's output registers (which are physically placed near
  -- bit_packer, far from byte_stuffer's stage 1 slices). Sampling the
  -- inputs into local registers here lets the placer co-locate the source
  -- registers with the stage 1 LUT cone, shortening every routed hop in
  -- the iValidLen / iWord fanout. Cost: +1 cycle pipeline latency.
  --
  -- Stall behaviour: with the shadow, two input words are in flight when
  -- AlmFull asserts (one already captured in the shadow on the AlmFull
  -- cycle, plus the one stage 1 is committing). The FIFO's AlmFull margin
  -- (BURST_DEPTH - ALM_FULL_LEVEL = 2) absorbs both.
  ----------------------------------------------------------------------------
  signal sInWord     : std_logic_vector(IN_WIDTH - 1 downto 0);
  signal sInValidLen : unsigned(log2ceil(IN_WIDTH + 1) - 1 downto 0);
  signal sInValid    : std_logic;
  signal sInFlush    : std_logic;
  signal sInTake     : std_logic;

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
  signal sHold     : std_logic_vector(HOLD_BITS - 1 downto 0);
  signal sHoldBits : unsigned(log2ceil(HOLD_BITS + 1) - 1 downto 0);
  signal sHoldLast : std_logic;
  signal sPrevFF   : std_logic;

  signal sOutWordReg  : std_logic_vector(OUT_WIDTH - 1 downto 0);
  signal sOutValidReg : std_logic;
  signal sOutBytesReg : unsigned(log2ceil(OUT_BYTES_PER_CYCLE + 1) - 1 downto 0);
  signal sFlushDone   : std_logic;

  -- End-of-image partial-byte drain. When the parallel emit leaves a sub-byte
  -- residue (or a pending stuff '0' with no follow-up data), drain is
  -- flagged here and the padded final byte is *assembled combinationally
  -- inside the drain cycle itself* from the still-registered residue in
  -- sHold/sHoldBits/sPrevFF. This keeps the pad-byte assembly entirely
  -- off the main-cycle critical path (which would otherwise propagate
  -- from the 4-slot chain into the pad-byte slicing every cycle).
  signal sDrainPending : std_logic;

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
  -- INPUT SHADOW: copy iWord / iValidLen / iWordValid / iFlush into local
  -- registers so the placer can put them adjacent to the stage 1 LUT cone.
  -- iStall is intentionally NOT shadowed — keeping it combinational
  -- preserves single-cycle stall reaction; the captured word simply sits
  -- in the shadow until iStall releases.
  -------------------------------------------------------------------------------------------------------------------------
  -- Shadow doubles as a skid buffer: stage 1's accept-condition is mirrored
  -- back here so the shadow holds its word whenever stage 1 cannot consume
  -- (stall, FIFO AlmFull, or pending flush). Without this, the next cycle
  -- would overwrite the held word with whatever upstream is driving (often
  -- a cleared bus, since upstream's iWordValid pulse is single-cycle).
  sInTake <= '1' when sInValid = '1'
                  and iStall = '0'
                  and sFlushPending = '0'
                  and sFifoAlmFull = '0'
             else '0';

  input_reg_proc : process (iClk)
  begin
    if rising_edge(iClk) then
      if iRst = '1' then
        sInWord     <= (others => '0');
        sInValidLen <= (others => '0');
        sInValid    <= '0';
        sInFlush    <= '0';
      elsif sInValid = '0' or sInTake = '1' then
        sInWord     <= iWord;
        sInValidLen <= iValidLen;
        sInValid    <= iWordValid;
        sInFlush    <= iFlush;
      end if;
    end if;
  end process input_reg_proc;

  -------------------------------------------------------------------------------------------------------------------------
  -- STAGE 1: bit packer
  -- Append sInWord's top sInValidLen bits MSB-first into the accumulator;
  -- when >= FIFO_BYTES whole bytes are present (or any whole bytes under
  -- flush), pack them into a FIFO word with byte_count + last_flag.
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
        vValidLenInt := to_integer(sInValidLen);
        vFlushPend   := sFlushPending;
        vAccept      := (sFlushPending = '0') and (sFifoAlmFull = '0');

        sFifoInValid <= '0';

        -- Append input bits (MSB-first). No FF detect at this stage.
        if sInValid = '1' and iStall = '0' and vAccept then
          for i in 0 to IN_WIDTH - 1 loop
            if i < vValidLenInt then
              vAccum(ACCUM_BITS - 1 - vBitsInt) := sInWord(IN_WIDTH - 1 - i);
              vBitsInt                          := vBitsInt + 1;
            end if;
          end loop;
        end if;

        -- Flush entry: pad sub-byte residue to a byte boundary, mark pending.
        if sInFlush = '1' and iStall = '0' and vAccept then
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

          vDataWord := vAccum(ACCUM_BITS - 1 downto ACCUM_BITS - FIFO_BITS);
          sFifoInData <= vDataWord
            & vLastFlag
            & std_logic_vector(to_unsigned(vEmitBytes, COUNT_W));
          sFifoInValid <= '1';

          vAccum   := std_logic_vector(shift_left(unsigned(vAccum), vEmitBytes * 8));
          vBitsInt := vBitsInt - vEmitBytes * 8;

        elsif vFlushPend = '1' and vBitsInt = 0 and sFifoAlmFull = '0' then
          -- Edge case: flush latched but accumulator already empty
          -- (no payload bytes for this image). Emit a count=0 sentinel.
          sFifoInData <= (FIFO_WIDTH - 1 downto LAST_POS + 1 => '0')
            & '1'
            & std_logic_vector(to_unsigned(0, COUNT_W));
          sFifoInValid <= '1';
          vFlushPend := '0';
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
    generic map(
      Width_g        => FIFO_WIDTH,
      Depth_g        => BURST_DEPTH,
      AlmFullOn_g    => true,
      AlmFullLevel_g => ALM_FULL_LEVEL,
      RamStyle_g     => "block",
      RamBehavior_g  => "RBW"
    )
    port map
    (
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
    and sDrainPending = '0'
    else
    '0';
  -- Pop FIFO when the skid buffer is empty or being drained this cycle.
  sFifoOutReady <= '1' when sStgValid = '0' or sStgTaken = '1' else
    '0';

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
    variable vHold     : std_logic_vector(HOLD_BITS - 1 downto 0);
    variable vHoldBits : natural range 0 to HOLD_BITS;
    variable vHoldLast : std_logic;
    variable vPrevFF   : std_logic;

    variable vPopBytes : natural range 0 to FIFO_BYTES;
    variable vPopLast  : std_logic;
    variable vPopData  : std_logic_vector(FIFO_BITS - 1 downto 0);

    -- Parallel-precomputed FF-equality flags for the 8 fixed candidate
    -- byte windows the chain can ever pick from.
    variable ff0              : std_logic; -- offset 0
    variable ff1a, ff1b       : std_logic; -- offsets 7, 8
    variable ff2a, ff2b       : std_logic; -- offsets 15, 16
    variable ff3a, ff3b, ff3c : std_logic; -- offsets 22, 23, 24

    -- Per-slot chain state.
    variable s0, s1, s2, s3, s4         : std_logic;
    variable a0, a1, a2, a3             : std_logic;
    variable cons0, cons1, cons2, cons3 : natural range 7 to 8;
    variable off1, off2, off3           : natural range 0 to 24;
    variable byte0, byte1, byte2, byte3 : std_logic_vector(7 downto 0);
    variable cum1, cum2                 : natural range 0 to 24;
    variable totalCons                  : natural range 0 to 32;

    variable vEmitData   : std_logic_vector(OUT_WIDTH - 1 downto 0);
    variable vEmitBytes  : natural range 0 to OUT_BYTES_PER_CYCLE;
    variable vConsumed   : natural range 0 to 32;
    variable vEmitLastFF : std_logic;
    variable vPadByte    : std_logic_vector(7 downto 0);
  begin
    if rising_edge(iClk) then

      if iRst = '1' then
        sHold         <= (others => '0');
        sHoldBits     <= (others => '0');
        sHoldLast     <= '0';
        sPrevFF       <= '0';
        sOutWordReg   <= (others => '0');
        sOutValidReg  <= '0';
        sOutBytesReg  <= (others => '0');
        sFlushDone    <= '0';
        sDrainPending <= '0';

      elsif sDrainPending = '1' then
        -- Assemble the partial pad byte combinationally from the residue
        -- left in sHold / sHoldBits / sPrevFF by the previous (drain-entry)
        -- cycle, then emit. The assembly is short (variable shift of at
        -- most 7 bits + zero pad + optional MSB stuff '0') and runs in
        -- isolation from the main 4-slot chain, so it does not extend
        -- the main-cycle critical path.
        if iStall = '0' then
          vHoldBits := to_integer(sHoldBits);
          vPadByte  := (others => '0');
          if sPrevFF = '1' then
            -- Stuff '0' at MSB, up to 7 real bits below it, zero pad.
            if vHoldBits > 0 then
              vPadByte(6 downto 7 - vHoldBits) :=
                sHold(HOLD_BITS - 1 downto HOLD_BITS - vHoldBits);
            end if;
          else
            -- Real bits at MSB, zero pad in LSBs.
            vPadByte(7 downto 8 - vHoldBits) :=
              sHold(HOLD_BITS - 1 downto HOLD_BITS - vHoldBits);
          end if;
          sOutWordReg(OUT_WIDTH - 1 downto OUT_WIDTH - 8) <= vPadByte;
          sOutWordReg(OUT_WIDTH - 9 downto 0)             <= (others => '0');
          sOutBytesReg                                    <= to_unsigned(1, sOutBytesReg'length);
          sOutValidReg                                    <= '1';
          sFlushDone                                      <= '1';
          sDrainPending                                   <= '0';
          sHoldLast                                       <= '0';
          sPrevFF                                         <= '0';
          sHold                                           <= (others => '0');
          sHoldBits                                       <= (others => '0');
        else
          sOutValidReg <= '0';
          sFlushDone   <= '0';
        end if;

      else

        vHold      := sHold;
        vHoldBits  := to_integer(sHoldBits);
        vHoldLast  := sHoldLast;
        vPrevFF    := sPrevFF;
        vEmitBytes := 0;
        vEmitData  := (others => '0');
        vConsumed  := 0;
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
        -- (2) Parallel-precompute FF flags for the 8 fixed candidate byte
        --     windows. These are pure 8-bit equality checks on fixed slices
        --     of vHold (depth = 1 LUT level after a wide AND/OR reduction).
        ----------------------------------------------------------------------
        ff0  := bool2bit(vHold(HOLD_BITS - 1 downto HOLD_BITS - 8) = x"FF");
        ff1a := bool2bit(vHold(HOLD_BITS - 8 downto HOLD_BITS - 15) = x"FF");
        ff1b := bool2bit(vHold(HOLD_BITS - 9 downto HOLD_BITS - 16) = x"FF");
        ff2a := bool2bit(vHold(HOLD_BITS - 16 downto HOLD_BITS - 23) = x"FF");
        ff2b := bool2bit(vHold(HOLD_BITS - 17 downto HOLD_BITS - 24) = x"FF");
        ff3a := bool2bit(vHold(HOLD_BITS - 23 downto HOLD_BITS - 30) = x"FF");
        ff3b := bool2bit(vHold(HOLD_BITS - 24 downto HOLD_BITS - 31) = x"FF");
        ff3c := bool2bit(vHold(HOLD_BITS - 25 downto HOLD_BITS - 32) = x"FF");

        ----------------------------------------------------------------------
        -- (3) Resolve the 4-step chain. Each step is a small mux + 1 AND.
        -- Invariant: if prev_FF_in = '1' the output byte's MSB is the stuff
        -- '0', so the byte cannot be 0xFF and prev_FF_out is forced to '0'.
        -- This forbids two consecutive prev_FF='1' entries in the chain,
        -- which keeps each subsequent slot's offset candidate set tiny.
        ----------------------------------------------------------------------
        s0 := vPrevFF;

        -- Slot 0 (offset 0)
        if s0 = '1' then
          byte0 := '0' & vHold(HOLD_BITS - 1 downto HOLD_BITS - 7);
          cons0 := 7;
        else
          byte0 := vHold(HOLD_BITS - 1 downto HOLD_BITS - 8);
          cons0 := 8;
        end if;
        a0   := ff0;
        s1   := (not s0) and a0;
        off1 := cons0;

        -- Slot 1 (offset 7 or 8)
        if off1 = 7 then
          a1 := ff1a;
          if s1 = '1' then
            byte1 := '0' & vHold(HOLD_BITS - 8 downto HOLD_BITS - 14);
          else
            byte1 := vHold(HOLD_BITS - 8 downto HOLD_BITS - 15);
          end if;
        else
          a1 := ff1b;
          if s1 = '1' then
            byte1 := '0' & vHold(HOLD_BITS - 9 downto HOLD_BITS - 15);
          else
            byte1 := vHold(HOLD_BITS - 9 downto HOLD_BITS - 16);
          end if;
        end if;
        if s1 = '1' then
          cons1 := 7;
        else
          cons1 := 8;
        end if;
        s2   := (not s1) and a1;
        off2 := off1 + cons1;

        -- Slot 2 (offset 15 or 16)
        if off2 = 15 then
          a2 := ff2a;
          if s2 = '1' then
            byte2 := '0' & vHold(HOLD_BITS - 16 downto HOLD_BITS - 22);
          else
            byte2 := vHold(HOLD_BITS - 16 downto HOLD_BITS - 23);
          end if;
        else
          a2 := ff2b;
          if s2 = '1' then
            byte2 := '0' & vHold(HOLD_BITS - 17 downto HOLD_BITS - 23);
          else
            byte2 := vHold(HOLD_BITS - 17 downto HOLD_BITS - 24);
          end if;
        end if;
        if s2 = '1' then
          cons2 := 7;
        else
          cons2 := 8;
        end if;
        s3   := (not s2) and a2;
        off3 := off2 + cons2;

        -- Slot 3 (offset 22, 23, or 24)
        if off3 = 22 then
          a3 := ff3a;
          if s3 = '1' then
            byte3 := '0' & vHold(HOLD_BITS - 23 downto HOLD_BITS - 29);
          else
            byte3 := vHold(HOLD_BITS - 23 downto HOLD_BITS - 30);
          end if;
        elsif off3 = 23 then
          a3 := ff3b;
          if s3 = '1' then
            byte3 := '0' & vHold(HOLD_BITS - 24 downto HOLD_BITS - 30);
          else
            byte3 := vHold(HOLD_BITS - 24 downto HOLD_BITS - 31);
          end if;
        else
          a3 := ff3c;
          if s3 = '1' then
            byte3 := '0' & vHold(HOLD_BITS - 25 downto HOLD_BITS - 31);
          else
            byte3 := vHold(HOLD_BITS - 25 downto HOLD_BITS - 32);
          end if;
        end if;
        if s3 = '1' then
          cons3 := 7;
        else
          cons3 := 8;
        end if;
        s4        := (not s3) and a3;
        cum1      := cons0;
        cum2      := cons0 + cons1;
        totalCons := cons0 + cons1 + cons2 + cons3;

        ----------------------------------------------------------------------
        -- (4) Pick emit count from how much of the chain's consumption is
        --     covered by vHoldBits. This is the *only* place sHoldBits gates
        --     output, so partial fills naturally degrade to 1..3 byte beats.
        ----------------------------------------------------------------------
        if iStall = '1' then
          vEmitBytes  := 0;
          vConsumed   := 0;
          vEmitLastFF := s0;
        elsif vHoldBits >= totalCons then
          vEmitBytes  := 4;
          vConsumed   := totalCons;
          vEmitLastFF := s4;
        elsif vHoldBits >= cum2 + cons2 then
          vEmitBytes  := 3;
          vConsumed   := cum2 + cons2;
          vEmitLastFF := s3;
        elsif vHoldBits >= cum2 then
          vEmitBytes  := 2;
          vConsumed   := cum2;
          vEmitLastFF := s2;
        elsif vHoldBits >= cum1 then
          vEmitBytes  := 1;
          vConsumed   := cum1;
          vEmitLastFF := s1;
        else
          vEmitBytes  := 0;
          vConsumed   := 0;
          vEmitLastFF := s0;
        end if;

        ----------------------------------------------------------------------
        -- (5) Pack output and shift hold by the total bits consumed.
        ----------------------------------------------------------------------
        if vEmitBytes >= 1 then
          vEmitData(OUT_WIDTH - 1 downto OUT_WIDTH - 8) := byte0;
        end if;
        if vEmitBytes >= 2 then
          vEmitData(OUT_WIDTH - 9 downto OUT_WIDTH - 16) := byte1;
        end if;
        if vEmitBytes >= 3 then
          vEmitData(OUT_WIDTH - 17 downto OUT_WIDTH - 24) := byte2;
        end if;
        if vEmitBytes >= 4 then
          vEmitData(OUT_WIDTH - 25 downto OUT_WIDTH - 32) := byte3;
        end if;

        if vEmitBytes > 0 then
          vHold     := std_logic_vector(shift_left(unsigned(vHold), vConsumed));
          vHoldBits := vHoldBits - vConsumed;
          vPrevFF   := vEmitLastFF;
        end if;

        ----------------------------------------------------------------------
        -- (6) Output register and flush-done / drain entry.
        ----------------------------------------------------------------------
        if vEmitBytes > 0 then
          sOutWordReg  <= vEmitData;
          sOutBytesReg <= to_unsigned(vEmitBytes, sOutBytesReg'length);
          sOutValidReg <= '1';

          if vHoldLast = '1' and vHoldBits = 0 and vPrevFF = '0' then
            -- Clean end: the final data byte was just emitted, no pad needed.
            sFlushDone <= '1';
            vHoldLast := '0';
          end if;
        else
          sOutValidReg <= '0';
        end if;

        -- Partial-residue / pending-stuff drain: flag drain and let the
        -- residue stay in sHold / sHoldBits / sPrevFF. The drain cycle
        -- reads those regs and assembles the padded byte combinationally
        -- (see the elsif sDrainPending branch). Keeping the assembly out
        -- of this cycle removes 4-5 LUT levels from the main critical path.
        if iStall = '0'
          and vHoldLast = '1'
          and vHoldBits < 8
          and (vHoldBits > 0 or vPrevFF = '1') then
          sDrainPending <= '1';
        end if;

        sHold     <= vHold;
        sHoldBits <= to_unsigned(vHoldBits, sHoldBits'length);
        sHoldLast <= vHoldLast;
        sPrevFF   <= vPrevFF;

      end if;
    end if;
  end process stage3_proc;

end architecture Behavioral;
