----------------------------------------------------------------------------------
-- Engineer:    Vitor Mendes Camilo
--
-- Module Name: A11_2_bit_packer - Behavioral
-- Description:
--
-- Notes:
--              Concatenates this cycle's raw + Golomb fields into a single
--              variable-length word. Output is (oWord, oValidLen): MSB-aligned
--              bitstream in oWord, oValidLen counts how many top bits are
--              meaningful. Downstream byte_stuffer accumulates these
--              variable-length words and produces byte-aligned output.
--
--              Word layout (MSB → LSB):
--                [raw bits (rawLen)][unary zeros (unaryZeros)]['1'][suffix (suffixLen)]
--
--              When only one of raw/Golomb fires, the corresponding portion is
--              omitted. Both fire simultaneously in RI (run-interruption) mode.
--
--              No internal buffer. Concat is combinational on the inputs;
--              outputs are registered to break the comb chain into byte_stuffer.
--
----------------------------------------------------------------------------------
use work.Common.all;

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

library openlogic_base;
use openlogic_base.olo_base_pkg_math.log2ceil;

entity A11_2_bit_packer is
  generic (
    LIMIT           : natural := CO_LIMIT_STD;
    UNARY_WIDTH     : natural := CO_UNARY_WIDTH_STD;
    SUFFIX_WIDTH    : natural := CO_SUFFIX_WIDTH_STD;
    SUFFIXLEN_WIDTH : natural := CO_SUFFIXLEN_WIDTH_STD;
    OUT_WIDTH       : natural := CO_LIMIT_STD
  );
  port (
    iClk   : in std_logic;
    iRst   : in std_logic;
    iStall : in std_logic;
    -- Raw bits interface - A.15 boundary bits, A.16 break residual (Sporadic raws & RI)
    iRawValid : in std_logic;
    iRawLen   : in unsigned(SUFFIXLEN_WIDTH - 1 downto 0);
    iRawVal   : in unsigned(SUFFIX_WIDTH - 1 downto 0);
    -- Golomb interface (regular mode & RI)
    iGolombValid : in std_logic;
    iUnaryZeros  : in unsigned(UNARY_WIDTH - 1 downto 0);
    iSuffixLen   : in unsigned(SUFFIXLEN_WIDTH - 1 downto 0);
    iSuffixVal   : in unsigned(SUFFIX_WIDTH - 1 downto 0);
    -- Output: MSB-aligned variable-length word
    oWord      : out std_logic_vector(OUT_WIDTH - 1 downto 0);
    oWordValid : out std_logic;
    oValidLen  : out unsigned(log2ceil(OUT_WIDTH + 1) - 1 downto 0)
  );
end entity A11_2_bit_packer;

architecture Behavioral of A11_2_bit_packer is

  signal sCombWord  : std_logic_vector(OUT_WIDTH - 1 downto 0);
  signal sCombValid : std_logic;
  signal sCombLen   : unsigned(log2ceil(OUT_WIDTH + 1) - 1 downto 0);

begin

  assert OUT_WIDTH >= LIMIT
  report "A11_2_bit_packer: OUT_WIDTH must be >= LIMIT (per-cycle worst case)"
    severity failure;

  -------------------------------------------------------------------------------------------------------------------------
  -- COMBINATORIAL PROCESS 
  -------------------------------------------------------------------------------------------------------------------------
  comb_proc : process (iRawValid, iRawLen, iRawVal, iGolombValid, iUnaryZeros, iSuffixLen, iSuffixVal)
    constant GOLOMB_WIDTH : natural := LIMIT;
    variable vWord        : unsigned(OUT_WIDTH - 1 downto 0);
    variable vMarker      : unsigned(GOLOMB_WIDTH - 1 downto 0);
    variable vGolombWord  : unsigned(GOLOMB_WIDTH - 1 downto 0);
    variable vGolombShift : unsigned(OUT_WIDTH - 1 downto 0);
    variable vRawShift    : unsigned(OUT_WIDTH - 1 downto 0);
    variable vRawLen      : natural;
    variable vSufLen      : natural;
    variable vGolombLen   : natural;
    variable vTotal       : natural;
  begin

    vWord   := (others => '0');
    vRawLen := to_integer(iRawLen);
    vSufLen := to_integer(iSuffixLen);
    vTotal  := 0;

    if iRawValid = '1' and vRawLen > 0 then
      vRawShift := shift_left(resize(iRawVal, OUT_WIDTH), OUT_WIDTH - vRawLen);
      vWord     := vRawShift;
      vTotal    := vRawLen;
    end if;

    if iGolombValid = '1' then
      vMarker     := shift_left(to_unsigned(1, GOLOMB_WIDTH), vSufLen);
      vGolombWord := vMarker or (resize(iSuffixVal, GOLOMB_WIDTH) and (vMarker - 1)); -- Masks the desired suffix bits and adds to marker

      vGolombLen   := to_integer(iUnaryZeros) + 1 + vSufLen;
      vGolombShift := shift_left(resize(vGolombWord, OUT_WIDTH), OUT_WIDTH - vTotal - vGolombLen);

      vWord  := vWord or vGolombShift;
      vTotal := vTotal + vGolombLen;
    end if;

    sCombWord  <= std_logic_vector(vWord);
    sCombLen   <= to_unsigned(vTotal, sCombLen'length);
    sCombValid <= iRawValid or iGolombValid;
  end process comb_proc;

  -------------------------------------------------------------------------------------------------------------------------
  -- SYNCHRONOUS PROCESS 
  -------------------------------------------------------------------------------------------------------------------------
  sync_proc : process (iClk)
  begin
    if rising_edge(iClk) then
      if iRst = '1' then
        oWord      <= (others => '0');
        oWordValid <= '0';
        oValidLen  <= (others => '0');
      elsif iStall = '0' then
        oWord      <= sCombWord;
        oWordValid <= sCombValid;
        oValidLen  <= sCombLen;
      end if;
    end if;
  end process sync_proc;

end architecture Behavioral;
