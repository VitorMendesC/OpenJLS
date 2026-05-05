----------------------------------------------------------------------------------
-- Engineer:    Vitor Mendes Camilo
--
-- Module Name: byte_stuffer - Behavioral
-- Description:
--
-- Notes:
--              Per T.87: every 0xFF byte in the encoded bitstream must be
--              followed by a stuffed zero bit so that decoders can distinguish
--              data from markers (0xFF followed by a non-zero byte).
--
--              Sits downstream of A11_2_bit_packer, which emits a variable-
--              length word per cycle: (iWord, iWordValid, iValidLen) - top
--              iValidLen bits of iWord are meaningful, MSB-first.
--
--              Two-stage internal pipeline (latency = 2 cycles input -> output):
--                Stage 1 - bit_accumulator:
--                  Concatenates sub-byte residue with iWord's valid bits.
--                  Extracts complete bytes; new residue (0..7 bits) carries.
--                  No FF logic - keeps comb depth shallow (one barrel shift).
--                Stage 2 - ff_stuffer:
--                  Receives byte stream from stage 1. Detects 0xFF bytes in
--                  parallel and inserts a single '0' bit immediately after
--                  each one via prefix-sum positioning + parallel barrel-OR.
--                  Output is byte-aligned modulo a sub-byte residue.
--
--              iFlush: zero-pad the residue up to a byte boundary across both
--                      stages, emit remaining bytes, reset trackers for the
--                      next image. Single-cycle pulse.
--
-- Assumptions:
--              OUT_WIDTH must be a multiple of 8.
--              BUFFER_WIDTH >= IN_WIDTH + IN_WIDTH/8 + 7
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
    IN_WIDTH     : natural := CO_LIMIT_STD;
    OUT_WIDTH    : natural := math_ceil_div(CO_LIMIT_STD + CO_LIMIT_STD / 8 + 7, 8) * 8;
    BUFFER_WIDTH : natural := 2 * CO_LIMIT_STD + CO_LIMIT_STD / 8
  );
  port (
    iClk        : in std_logic;
    iRst        : in std_logic;
    iStall      : in std_logic;
    iWord       : in std_logic_vector(IN_WIDTH - 1 downto 0);
    iWordValid  : in std_logic;
    iValidLen   : in unsigned(log2ceil(IN_WIDTH + 1) - 1 downto 0);
    iFlush      : in std_logic;
    oWord       : out std_logic_vector(OUT_WIDTH - 1 downto 0);
    oWordValid  : out std_logic;
    oValidBytes : out unsigned(log2ceil(OUT_WIDTH / 8 + 1) - 1 downto 0)
  );
end entity byte_stuffer;

architecture Behavioral of byte_stuffer is

  -- Stage 1 internal sizing
  constant S1_MAX_BYTES : natural := math_ceil_div(IN_WIDTH + 7, 8);
  constant S1_BYTES_W   : natural := S1_MAX_BYTES * 8;
  constant CAT_WIDTH    : natural := 8 + IN_WIDTH;

  -- Stage 1 state (sub-byte residue from accumulator)
  signal sResidue    : std_logic_vector(7 downto 0);
  signal sResidueLen : unsigned(2 downto 0);

  -- Stage 1 -> Stage 2 pipeline registers
  signal s1Bytes : std_logic_vector(S1_BYTES_W - 1 downto 0);
  signal s1Count : unsigned(log2ceil(S1_MAX_BYTES + 2) - 1 downto 0);
  signal s1Valid : std_logic;
  signal s1Flush : std_logic;

  -- Stage 2 state (sub-byte residue from stuffer + bit buffer)
  signal sBitBuf    : std_logic_vector(BUFFER_WIDTH - 1 downto 0);
  signal sBitBufLen : unsigned(log2ceil(BUFFER_WIDTH + 1) - 1 downto 0);

  -- Output regs
  signal sOutWordBuffer : std_logic_vector(OUT_WIDTH - 1 downto 0);
  signal sValidBytes    : unsigned(log2ceil(OUT_WIDTH / 8 + 1) - 1 downto 0);
  signal sWordValidBuf  : std_logic;

  type byte_array_t is array(0 to S1_MAX_BYTES - 1) of std_logic_vector(7 downto 0);
  type pos_array_t is array(0 to S1_MAX_BYTES) of natural range 0 to BUFFER_WIDTH;

begin

  assert OUT_WIDTH mod 8 = 0
  report "byte_stuffer: OUT_WIDTH must be a multiple of 8"
    severity failure;

  assert BUFFER_WIDTH >= IN_WIDTH + math_ceil_div(IN_WIDTH, 8) + 7
  report "byte_stuffer: BUFFER_WIDTH too small for one-cycle worst case (residue + input + stuffing)"
    severity failure;

  assert OUT_WIDTH >= math_ceil_div(IN_WIDTH + math_ceil_div(IN_WIDTH, 8) + 7, 8) * 8
  report "byte_stuffer: OUT_WIDTH too small to drain worst-case input in one cycle (residue invariant)"
    severity failure;

  oWord       <= sOutWordBuffer;
  oWordValid  <= sWordValidBuf;
  oValidBytes <= sValidBytes;

  -------------------------------------------------------------------------------------------------------------------------
  -- STAGE 1: BIT ACCUMULATOR (no FF logic)
  -------------------------------------------------------------------------------------------------------------------------
  stage1_proc : process (iClk)
    variable vCat         : unsigned(CAT_WIDTH - 1 downto 0);
    variable vIWordPos    : unsigned(CAT_WIDTH - 1 downto 0);
    variable vResPos      : unsigned(CAT_WIDTH - 1 downto 0);
    variable vCatShifted  : unsigned(CAT_WIDTH - 1 downto 0);
    variable vTotal       : natural;
    variable vBytes       : natural;
    variable vNewResLen   : natural;
    variable vValidLenInt : natural;
    variable vS1Bytes     : std_logic_vector(S1_BYTES_W - 1 downto 0);
  begin
    if rising_edge(iClk) then
      if iRst = '1' then
        sResidue    <= (others => '0');
        sResidueLen <= (others => '0');
        s1Bytes     <= (others => '0');
        s1Count     <= (others => '0');
        s1Valid     <= '0';
        s1Flush     <= '0';
      elsif iStall = '0' then
        s1Valid <= '0';
        s1Flush <= '0';

        if iWordValid = '1' or iFlush = '1' then
          if iWordValid = '1' then
            vValidLenInt := to_integer(iValidLen);
          else
            vValidLenInt := 0;
          end if;

          -- Residue at top 8 bits of CAT, MSB-aligned.
          vResPos := shift_left(resize(unsigned(sResidue), CAT_WIDTH), IN_WIDTH);

          -- iWord MSB-aligned in CAT, then shift down by sResidueLen so its
          -- valid bits start right after residue's valid bits.
          vIWordPos := shift_right(
            shift_left(resize(unsigned(iWord), CAT_WIDTH), CAT_WIDTH - IN_WIDTH),
            to_integer(sResidueLen));

          vCat := vResPos or vIWordPos;

          vTotal     := to_integer(sResidueLen) + vValidLenInt;
          vBytes     := vTotal / 8;
          vNewResLen := vTotal mod 8;

          -- Flush: pad residue out as one extra byte (low bits already 0).
          if iFlush = '1' and vNewResLen > 0 then
            vBytes     := vBytes + 1;
            vNewResLen := 0;
          end if;

          if CAT_WIDTH >= S1_BYTES_W then
            vS1Bytes := std_logic_vector(vCat(CAT_WIDTH - 1 downto CAT_WIDTH - S1_BYTES_W));
          else
            vS1Bytes                                               := (others => '0');
            vS1Bytes(S1_BYTES_W - 1 downto S1_BYTES_W - CAT_WIDTH) := std_logic_vector(vCat);
          end if;

          s1Bytes <= vS1Bytes;
          s1Count <= to_unsigned(vBytes, s1Count'length);
          s1Valid <= iWordValid;
          s1Flush <= iFlush;

          if iFlush = '1' then
            sResidue    <= (others => '0');
            sResidueLen <= (others => '0');
          else
            vCatShifted := shift_left(vCat, vBytes * 8);
            sResidue    <= std_logic_vector(vCatShifted(CAT_WIDTH - 1 downto CAT_WIDTH - 8));
            sResidueLen <= to_unsigned(vNewResLen, sResidueLen'length);
          end if;
        end if;
      end if;
    end if;
  end process stage1_proc;

  -------------------------------------------------------------------------------------------------------------------------
  -- STAGE 2: FF STUFFER (parallel detect + prefix-sum positioning)
  -------------------------------------------------------------------------------------------------------------------------
  stage2_proc : process (iClk)
    variable vBytes_arr      : byte_array_t;
    variable vFF             : std_logic_vector(S1_MAX_BYTES - 1 downto 0);
    variable vPos            : pos_array_t;
    variable vS1CountInt     : natural;
    variable vBitBufNew      : unsigned(BUFFER_WIDTH - 1 downto 0);
    variable vAdded          : unsigned(BUFFER_WIDTH - 1 downto 0);
    variable vBitBufLenInt   : natural;
    variable vBitBufFinalLen : natural;
    variable vBytesOut       : natural;
    variable vShiftAmt       : natural;
  begin
    if rising_edge(iClk) then
      if iRst = '1' then
        sBitBuf        <= (others => '0');
        sBitBufLen     <= (others => '0');
        sOutWordBuffer <= (others => '0');
        sValidBytes    <= (others => '0');
        sWordValidBuf  <= '0';
      elsif iStall = '0' then
        sWordValidBuf <= '0';

        if s1Valid = '1' or s1Flush = '1' then
          vS1CountInt   := to_integer(s1Count);
          vBitBufLenInt := to_integer(sBitBufLen);
          vBitBufNew    := unsigned(sBitBuf);

          for k in 0 to S1_MAX_BYTES - 1 loop
            vBytes_arr(k) := s1Bytes(S1_BYTES_W - 1 - k * 8 downto S1_BYTES_W - (k + 1) * 8);
          end loop;

          for k in 0 to S1_MAX_BYTES - 1 loop
            if k < vS1CountInt and vBytes_arr(k) = "11111111" then
              vFF(k) := '1';
            else
              vFF(k) := '0';
            end if;
          end loop;

          vPos(0) := vBitBufLenInt;
          for k in 0 to S1_MAX_BYTES - 1 loop
            if k < vS1CountInt then
              if vFF(k) = '1' then
                vPos(k + 1) := vPos(k) + 9;
              else
                vPos(k + 1) := vPos(k) + 8;
              end if;
            else
              vPos(k + 1) := vPos(k);
            end if;
          end loop;

          for k in 0 to S1_MAX_BYTES - 1 loop
            if k < vS1CountInt then
              vShiftAmt  := BUFFER_WIDTH - 8 - vPos(k);
              vAdded     := shift_left(resize(unsigned(vBytes_arr(k)), BUFFER_WIDTH), vShiftAmt);
              vBitBufNew := vBitBufNew or vAdded;
            end if;
          end loop;

          vBitBufFinalLen := vPos(S1_MAX_BYTES);

          if s1Flush = '1' and (vBitBufFinalLen mod 8) /= 0 then
            vBitBufFinalLen := ((vBitBufFinalLen + 7) / 8) * 8;
          end if;

          vBytesOut := vBitBufFinalLen / 8;
          if vBytesOut > OUT_WIDTH / 8 then
            vBytesOut := OUT_WIDTH / 8;
          end if;

          sOutWordBuffer <= std_logic_vector(vBitBufNew(BUFFER_WIDTH - 1 downto BUFFER_WIDTH - OUT_WIDTH));
          sValidBytes    <= to_unsigned(vBytesOut, sValidBytes'length);

          if vBytesOut > 0 then
            sWordValidBuf <= '1';
          else
            sWordValidBuf <= '0';
          end if;

          if s1Flush = '1' then
            sBitBuf    <= (others => '0');
            sBitBufLen <= (others => '0');
          else
            vBitBufNew := shift_left(vBitBufNew, vBytesOut * 8);
            sBitBuf    <= std_logic_vector(vBitBufNew);
            sBitBufLen <= to_unsigned(vBitBufFinalLen - vBytesOut * 8, sBitBufLen'length);
          end if;
        end if;
      end if;
    end if;
  end process stage2_proc;

end architecture Behavioral;
