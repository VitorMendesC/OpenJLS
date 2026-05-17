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
--   Three internal stages:
--
--     Stage 1 — bit packer:
--       Accumulates input bits MSB-first into a wide accumulator. 
--       When >= FIFO_BYTES whole bytes are present, packs them
--       into a fixed-width FIFO word together with a byte-count and a
--       last_flag. Critical path: one barrel shift over IN_WIDTH bits.
--
--     Stage 2 — BRAM-backed sync FIFO
--
--     Stage 3 — FF stuffer + output emit:
--       Refills a holding register from FIFO pops. Each cycle forms up to
--       OUT_BYTES_PER_CYCLE output bytes via:
--         (a) a parallel pre-compute of FF-equality flags over the 8 fixed
--             candidate byte windows that any of the 4 slots could ever
--             read from (offsets 0, 7, 8, 15, 16, 22, 23, 24);
--         (b) a 4-step chain over the slots that resolves each slot's input
--             prev_FF and selects the correct candidate flag/bits via a
--             small mux.
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

  -- Stage 1 sizing
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

  function almost_full_level(depth : natural) return natural is
  begin
    if depth >= 4 then
      return depth - 2;
    elsif depth >= 2 then
      return depth - 1;
    else
      return depth;
    end if;
  end function;
  constant ALM_FULL_LEVEL : natural := almost_full_level(BURST_DEPTH);

  -- Stage 3 holding register: room for at least one full FIFO pop on top of
  -- any leftover bits from the previous consume. Bits are stored MSB-first
  -- (oldest emitted first) at the top of the buffer.
  constant HOLD_BYTES : natural := 2 * FIFO_BYTES;
  constant HOLD_BITS  : natural := HOLD_BYTES * 8;

  -- Input registers
  signal sInWord     : std_logic_vector(IN_WIDTH - 1 downto 0);
  signal sInValidLen : unsigned(log2ceil(IN_WIDTH + 1) - 1 downto 0);
  signal sInValid    : std_logic;
  signal sInFlush    : std_logic;
  signal sInTake     : std_logic;

  -- Stage 1 accumulator
  signal sAccumBuffer    : std_logic_vector(ACCUM_BITS - 1 downto 0);
  signal sAccumCountBits : unsigned(log2ceil(ACCUM_BITS + 1) - 1 downto 0);
  signal sFlushPending   : std_logic;

  -- FIFO interface
  signal sFifoInData   : std_logic_vector(FIFO_WIDTH - 1 downto 0);
  signal sFifoInValid  : std_logic;
  signal sFifoInReady  : std_logic;
  signal sFifoOutData  : std_logic_vector(FIFO_WIDTH - 1 downto 0);
  signal sFifoOutValid : std_logic;
  signal sFifoOutReady : std_logic;
  signal sFifoAlmFull  : std_logic;

  -- Skid buffer between FIFO output and Stage 3 consume
  -- Helps timing
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

  -- End-of-image partial-byte drain
  signal sDrainPending : std_logic;

  -- End-of-image clean-end 
  signal sCleanEndPending : std_logic;

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
  -- INPUT REGISTERS
  -------------------------------------------------------------------------------------------------------------------------
  -- Helps timing; iStall is intentionally NOT registered; Works as a skid buffer

  sInTake <= '1' when sInValid = '1'
    and iStall = '0'
    and sFlushPending = '0'
    and sFifoAlmFull = '0'
    else
    '0';

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
  -- STAGE 1: Accumulator
  -------------------------------------------------------------------------------------------------------------------------
  -- Accumulates the variable length word from bit packer until its wide enough to fit
  -- in the FIFO, pack them as byte_count + last_flag.

  stage1_proc : process (iClk)
    variable vAccumBuffer    : std_logic_vector(ACCUM_BITS - 1 downto 0);
    variable vAccumCountBits : natural range 0 to ACCUM_BITS;
    variable vValidLenInt    : natural;
    variable vFlushPend      : std_logic;
    variable vAccept         : boolean;
    variable vPadBits        : natural;
    variable vBytesReady     : natural;
    variable vEmitBytes      : natural;
    variable vLastFlag       : std_logic;
    variable vDataWord       : std_logic_vector(FIFO_BITS - 1 downto 0);
  begin
    if rising_edge(iClk) then

      if iRst = '1' then
        sAccumBuffer    <= (others => '0');
        sAccumCountBits <= (others => '0');
        sFlushPending   <= '0';
        sFifoInValid    <= '0';
        sFifoInData     <= (others => '0');

      else

        vAccumBuffer    := sAccumBuffer;
        vAccumCountBits := to_integer(sAccumCountBits);
        vValidLenInt    := to_integer(sInValidLen);
        vFlushPend      := sFlushPending;
        vAccept         := (sFlushPending = '0') and (sFifoAlmFull = '0');

        sFifoInValid <= '0';

        ---------------------------------------------------------------------------------
        -- WRITE
        ---------------------------------------------------------------------------------
        -- Append input bits (MSB-first)
        if sInValid = '1' and iStall = '0' and vAccept then
          for i in 0 to IN_WIDTH - 1 loop
            if i < vValidLenInt then
              vAccumBuffer(ACCUM_BITS - 1 - vAccumCountBits) := sInWord(IN_WIDTH - 1 - i);
              vAccumCountBits                                := vAccumCountBits + 1;
            end if;
          end loop;
        end if;

        -- Flush entry: pad sub-byte residue to a byte boundary, mark pending.
        if sInFlush = '1' and iStall = '0' and vAccept then
          if (vAccumCountBits mod 8) /= 0 then
            vPadBits := 8 - (vAccumCountBits mod 8);
            for j in 0 to 7 loop
              if j < vPadBits then
                vAccumBuffer(ACCUM_BITS - 1 - vAccumCountBits) := '0';
                vAccumCountBits                                := vAccumCountBits + 1;
              end if;
            end loop;
          end if;
          vFlushPend := '1';
        end if;

        ---------------------------------------------------------------------------------
        -- READ
        ---------------------------------------------------------------------------------
        -- Drain FIFO_BYTES bytes into the FIFO when accumulated sufficient data

        vBytesReady := vAccumCountBits / 8;
        if vBytesReady > FIFO_BYTES then
          vBytesReady := FIFO_BYTES;
        end if;

        if vBytesReady > 0 and sFifoAlmFull = '0' then

          vEmitBytes := vBytesReady;
          if vFlushPend = '1' and (vAccumCountBits - vEmitBytes * 8) = 0 then
            vLastFlag  := '1';
            vFlushPend := '0';
          else
            vLastFlag := '0';
          end if;

          vDataWord := vAccumBuffer(ACCUM_BITS - 1 downto ACCUM_BITS - FIFO_BITS);
          sFifoInData <= vDataWord
            & vLastFlag
            & std_logic_vector(to_unsigned(vEmitBytes, COUNT_W));
          sFifoInValid <= '1';

          vAccumBuffer    := std_logic_vector(shift_left(unsigned(vAccumBuffer), vEmitBytes * 8));
          vAccumCountBits := vAccumCountBits - vEmitBytes * 8;

        elsif vFlushPend = '1' and vAccumCountBits = 0 and sFifoAlmFull = '0' then
          -- Edge case: flush latched but accumulator already empty
          -- (no payload bytes for this image). Emit a count=0 sentinel.
          sFifoInData <= (FIFO_WIDTH - 1 downto LAST_POS + 1 => '0')
            & '1'
            & std_logic_vector(to_unsigned(0, COUNT_W));
          sFifoInValid <= '1';
          vFlushPend := '0';
        end if;

        sAccumBuffer    <= vAccumBuffer;
        sAccumCountBits <= to_unsigned(vAccumCountBits, sAccumCountBits'length);
        sFlushPending   <= vFlushPend;

        assert vAccumCountBits <= ACCUM_BITS
        report "byte_stuffer: stage 1 accumulator overflow"
          severity failure;

      end if;
    end if;
  end process stage1_proc;

  -------------------------------------------------------------------------------------------------------------------------
  -- STAGE 2: FIFO
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
    and sCleanEndPending = '0'
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

    -- Per-slot chain state. With the log-depth parallel resolver below,
    -- each output is expressed directly as a function of (vPrevFF, ff
    -- flags, vHold); no per-slot offsets or cons values are materialized.
    variable s1, s2, s3, s4             : std_logic;
    variable byte0, byte1, byte2, byte3 : std_logic_vector(7 downto 0);
    variable cum1, cum2, cum3           : natural range 0 to 24;
    variable totalCons                  : natural range 0 to 32;

    variable vEmitData   : std_logic_vector(OUT_WIDTH - 1 downto 0);
    variable vEmitBytes  : natural range 0 to OUT_BYTES_PER_CYCLE;
    variable vConsumed   : natural range 0 to 32;
    variable vEmitLastFF : std_logic;
    variable vPadByte    : std_logic_vector(7 downto 0);

    -- Constant-subtract candidates for next-vHoldBits. Each is evaluated
    -- in parallel by synthesis (the operand is a literal, so each subtract
    -- collapses to a thin LUT+CARRY4 chain with no variable-side adder
    -- cone). The final case-mux below picks one by (vEmitBytes, vPrevFF,
    -- ff*). Replaces `vHoldBits - vConsumed`, where vConsumed was a
    -- variable derived from cum*/totalCons and pushed the subtract to the
    -- bottom of the Stage-3 next-state cone.
    variable hbMinus7  : integer range -32 to HOLD_BITS;
    variable hbMinus8  : integer range -32 to HOLD_BITS;
    variable hbMinus15 : integer range -32 to HOLD_BITS;
    variable hbMinus16 : integer range -32 to HOLD_BITS;
    variable hbMinus22 : integer range -32 to HOLD_BITS;
    variable hbMinus23 : integer range -32 to HOLD_BITS;
    variable hbMinus24 : integer range -32 to HOLD_BITS;
    variable hbMinus30 : integer range -32 to HOLD_BITS;
    variable hbMinus31 : integer range -32 to HOLD_BITS;
    variable hbMinus32 : integer range -32 to HOLD_BITS;
  begin
    if rising_edge(iClk) then

      if iRst = '1' then
        sHold            <= (others => '0');
        sHoldBits        <= (others => '0');
        sHoldLast        <= '0';
        sPrevFF          <= '0';
        sOutWordReg      <= (others => '0');
        sOutValidReg     <= '0';
        sOutBytesReg     <= (others => '0');
        sFlushDone       <= '0';
        sDrainPending    <= '0';
        sCleanEndPending <= '0';

      elsif sCleanEndPending = '1' then
        -- 0-byte EOI beat: framer (jls_framer.vhd:488-510) treats
        -- iValid='1' AND iByteEnable=0 AND iEOI='1' as "push FF D9 at
        -- current count" with no data copy.
        if iStall = '0' then
          sOutWordReg      <= (others => '0');
          sOutBytesReg     <= (others => '0');
          sOutValidReg     <= '1';
          sFlushDone       <= '1';
          sHoldLast        <= '0';
          sCleanEndPending <= '0';
        else
          sOutValidReg <= '0';
          sFlushDone   <= '0';
        end if;

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
        -- (3) Log-depth parallel-prefix resolver.
        --     The serial 4-step chain has been algebraically collapsed:
        --     every output (byte0..byte3, s1..s4, cum*, totalCons) is now
        --     written as a direct function of (vPrevFF, ff flags, vHold).
        --     Synthesis maps each output bit into a small flat mux (~2 LUT
        --     levels after the ff-equality compare) instead of a 4-deep
        --     dependency walk.
        --
        --     Invariant exploited: if prev_FF_in='1' for slot k, slot k's
        --     output byte starts with a stuff '0', so it cannot equal 0xFF
        --     and the next slot's prev_FF_in is forced to '0'. This
        --     eliminates two-adjacent-stuffs and bounds each slot's offset
        --     candidate set to {2..3} values, which is what makes the flat
        --     case tree small.
        ----------------------------------------------------------------------

        -- byte0 — slot 0 output, single mux on vPrevFF.
        case vPrevFF is
          when '1' =>
            byte0 := '0' & vHold(HOLD_BITS - 1 downto HOLD_BITS - 7);
          when others =>
            byte0 := vHold(HOLD_BITS - 1 downto HOLD_BITS - 8);
        end case;

        -- byte1 — depends on (vPrevFF, ff0).
        case vPrevFF is
          when '1' =>
            -- s1=0 forced, off1=7
            byte1 := vHold(HOLD_BITS - 8 downto HOLD_BITS - 15);
          when others =>
            -- off1=8, s1=ff0
            if ff0 = '1' then
              byte1 := '0' & vHold(HOLD_BITS - 9 downto HOLD_BITS - 15);
            else
              byte1 := vHold(HOLD_BITS - 9 downto HOLD_BITS - 16);
            end if;
        end case;

        -- byte2 — depends on (vPrevFF, ff0, ff1a/ff1b).
        case vPrevFF is
          when '1' =>
            -- s1=0, off2=15, s2=ff1a
            if ff1a = '1' then
              byte2 := '0' & vHold(HOLD_BITS - 16 downto HOLD_BITS - 22);
            else
              byte2 := vHold(HOLD_BITS - 16 downto HOLD_BITS - 23);
            end if;
          when others =>
            if ff0 = '1' then
              -- s1=1, s2=0 forced, off2=15
              byte2 := vHold(HOLD_BITS - 16 downto HOLD_BITS - 23);
            elsif ff1b = '1' then
              -- s1=0, s2=1, off2=16
              byte2 := '0' & vHold(HOLD_BITS - 17 downto HOLD_BITS - 23);
            else
              -- s1=0, s2=0, off2=16
              byte2 := vHold(HOLD_BITS - 17 downto HOLD_BITS - 24);
            end if;
        end case;

        -- byte3 — depends on (vPrevFF, ff0, ff1a/ff1b, ff2a/ff2b).
        case vPrevFF is
          when '1' =>
            if ff1a = '1' then
              -- s2=1, s3=0 forced, off3=22
              byte3 := vHold(HOLD_BITS - 23 downto HOLD_BITS - 30);
            else
              -- s2=0, off3=23, s3=ff2a
              if ff2a = '1' then
                byte3 := '0' & vHold(HOLD_BITS - 24 downto HOLD_BITS - 30);
              else
                byte3 := vHold(HOLD_BITS - 24 downto HOLD_BITS - 31);
              end if;
            end if;
          when others =>
            if ff0 = '1' then
              -- s2=0 forced, off3=23, s3=ff2a
              if ff2a = '1' then
                byte3 := '0' & vHold(HOLD_BITS - 24 downto HOLD_BITS - 30);
              else
                byte3 := vHold(HOLD_BITS - 24 downto HOLD_BITS - 31);
              end if;
            elsif ff1b = '1' then
              -- s2=1, s3=0 forced, off3=23
              byte3 := vHold(HOLD_BITS - 24 downto HOLD_BITS - 31);
            else
              -- s2=0, off3=24, s3=ff2b
              if ff2b = '1' then
                byte3 := '0' & vHold(HOLD_BITS - 25 downto HOLD_BITS - 31);
              else
                byte3 := vHold(HOLD_BITS - 25 downto HOLD_BITS - 32);
              end if;
            end if;
        end case;

        -- Intermediate s values used by the partial-emit selector.
        -- s_k = '1' iff byte_{k-1} (as actually emitted) equals 0xFF.

        -- s1: byte0 is FF iff vPrevFF=0 AND ff0=1.
        s1 := (not vPrevFF) and ff0;

        -- s2.
        case vPrevFF is
          when '1'    => s2    := ff1a;
          when others => s2 := (not ff0) and ff1b;
        end case;

        -- s3.
        case vPrevFF is
          when '1' =>
            if ff1a = '1' then
              s3 := '0';
            else
              s3 := ff2a;
            end if;
          when others =>
            if ff0 = '1' then
              s3 := ff2a;
            elsif ff1b = '1' then
              s3 := '0';
            else
              s3 := ff2b;
            end if;
        end case;

        -- s4 (= next-cycle vPrevFF when 4 bytes are emitted).
        case vPrevFF is
          when '1' =>
            if ff1a = '1' then
              s4 := ff3a;
            else
              s4 := (not ff2a) and ff3b;
            end if;
          when others =>
            if ff0 = '1' then
              s4 := (not ff2a) and ff3b;
            elsif ff1b = '1' then
              s4 := ff3b;
            else
              s4 := (not ff2b) and ff3c;
            end if;
        end case;

        -- Cumulative consumption thresholds (in bits).
        --   cum1 = cons0
        --   cum2 = cons0 + cons1
        --   cum3 = cons0 + cons1 + cons2
        --   totalCons = cum3 + cons3

        case vPrevFF is
          when '1'    => cum1    := 7;
          when others => cum1 := 8;
        end case;

        case vPrevFF is
          when '1'    => cum2 := 15;
          when others =>
            if ff0 = '1' then
              cum2 := 15;
            else
              cum2 := 16;
            end if;
        end case;

        case vPrevFF is
          when '1' =>
            if ff1a = '1' then
              cum3 := 22;
            else
              cum3 := 23;
            end if;
          when others =>
            if ff0 = '1' or ff1b = '1' then
              cum3 := 23;
            else
              cum3 := 24;
            end if;
        end case;

        case vPrevFF is
          when '1' =>
            if ff1a = '1' then
              totalCons := 30;
            else
              if ff2a = '1' then
                totalCons := 30;
              else
                totalCons := 31;
              end if;
            end if;
          when others =>
            if ff0 = '1' then
              if ff2a = '1' then
                totalCons := 30;
              else
                totalCons := 31;
              end if;
            elsif ff1b = '1' then
              totalCons := 31;
            else
              if ff2b = '1' then
                totalCons := 31;
              else
                totalCons := 32;
              end if;
            end if;
        end case;

        -- Parallel constant-subtract candidates (see variable decls).
        hbMinus7  := vHoldBits - 7;
        hbMinus8  := vHoldBits - 8;
        hbMinus15 := vHoldBits - 15;
        hbMinus16 := vHoldBits - 16;
        hbMinus22 := vHoldBits - 22;
        hbMinus23 := vHoldBits - 23;
        hbMinus24 := vHoldBits - 24;
        hbMinus30 := vHoldBits - 30;
        hbMinus31 := vHoldBits - 31;
        hbMinus32 := vHoldBits - 32;

        ----------------------------------------------------------------------
        -- (4) Pick emit count from how much of the chain's consumption is
        --     covered by vHoldBits. This is the *only* place sHoldBits gates
        --     output, so partial fills naturally degrade to 1..3 byte beats.
        ----------------------------------------------------------------------
        if iStall = '1' then
          vEmitBytes  := 0;
          vConsumed   := 0;
          vEmitLastFF := vPrevFF;
        elsif vHoldBits >= totalCons then
          vEmitBytes  := 4;
          vConsumed   := totalCons;
          vEmitLastFF := s4;
        elsif vHoldBits >= cum3 then
          vEmitBytes  := 3;
          vConsumed   := cum3;
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
          vEmitLastFF := vPrevFF;
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
          vHold := std_logic_vector(shift_left(unsigned(vHold), vConsumed));

          -- Mux precomputed constant subtracts to form next vHoldBits.
          -- Flag tests below use vPrevFF *before* it is updated to
          -- vEmitLastFF — same value that drove the cum*/totalCons
          -- selection above, so the case matches vConsumed exactly.
          -- The selected branch's value is >= 0 because vEmitBytes was
          -- only set when vHoldBits crossed the matching threshold.
          case vEmitBytes is
            when 1 =>
              if vPrevFF = '1' then
                vHoldBits := hbMinus7;
              else
                vHoldBits := hbMinus8;
              end if;
            when 2 =>
              if vPrevFF = '1' or ff0 = '1' then
                vHoldBits := hbMinus15;
              else
                vHoldBits := hbMinus16;
              end if;
            when 3 =>
              case vPrevFF is
                when '1' =>
                  if ff1a = '1' then
                    vHoldBits := hbMinus22;
                  else
                    vHoldBits := hbMinus23;
                  end if;
                when others =>
                  if ff0 = '1' or ff1b = '1' then
                    vHoldBits := hbMinus23;
                  else
                    vHoldBits := hbMinus24;
                  end if;
              end case;
            when others => -- vEmitBytes = 4
              case vPrevFF is
                when '1' =>
                  if ff1a = '1' or ff2a = '1' then
                    vHoldBits := hbMinus30;
                  else
                    vHoldBits := hbMinus31;
                  end if;
                when others =>
                  if ff0 = '1' then
                    if ff2a = '1' then
                      vHoldBits := hbMinus30;
                    else
                      vHoldBits := hbMinus31;
                    end if;
                  elsif ff1b = '1' then
                    vHoldBits := hbMinus31;
                  else
                    if ff2b = '1' then
                      vHoldBits := hbMinus31;
                    else
                      vHoldBits := hbMinus32;
                    end if;
                  end if;
              end case;
          end case;

          vPrevFF := vEmitLastFF;
        end if;

        ----------------------------------------------------------------------
        -- (6) Output register and flush-done / drain entry.
        ----------------------------------------------------------------------
        if vEmitBytes > 0 then
          sOutWordReg  <= vEmitData;
          sOutBytesReg <= to_unsigned(vEmitBytes, sOutBytesReg'length);
          sOutValidReg <= '1';

          if vHoldLast = '1' and vHoldBits = 0 and vPrevFF = '0' then
            sCleanEndPending <= '1';
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
