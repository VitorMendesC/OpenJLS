----------------------------------------------------------------------------------
-- Company:
-- Engineer:    Vitor Mendes Camilo
-- 
-- Create Date: 08/30/2025 07:55:00 PM
-- Module Name: A11_2_bit_packer - Behavioral
-- Description:  
-- 
-- Notes:
--              buffer is written from MSB, to match bitstream pattern
--
--              TODO: iFlush is unused
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
    OUT_WIDTH       : natural := CO_OUT_WIDTH_STD;
    BUFFER_WIDTH    : natural := CO_BUFFER_WIDTH_STD;
    UNARY_WIDTH     : natural := CO_UNARY_WIDTH_STD;
    SUFFIX_WIDTH    : natural := CO_SUFFIX_WIDTH_STD;
    SUFFIXLEN_WIDTH : natural := CO_SUFFIXLEN_WIDTH_STD
  );
  port (
    iClk            : in std_logic;
    iRst            : in std_logic;
    iFlush          : in std_logic;
    iValid          : in std_logic;
    iUnaryZeros     : in unsigned(UNARY_WIDTH - 1 downto 0);
    iSuffixLen      : in unsigned(SUFFIXLEN_WIDTH - 1 downto 0);
    iSuffixVal      : in unsigned(SUFFIX_WIDTH - 1 downto 0);
    iReady          : in std_logic;
    oWord           : out std_logic_vector(OUT_WIDTH - 1 downto 0);
    oWordValid      : out std_logic;
    oBufferOverflow : out std_logic
  );
end A11_2_bit_packer;

architecture Behavioral of A11_2_bit_packer is

  signal sBuffer          : std_logic_vector (BUFFER_WIDTH - 1 downto 0);
  signal sWritePointer    : unsigned (log2ceil(BUFFER_WIDTH) - 1 downto 0) := to_unsigned(BUFFER_WIDTH - 1, log2ceil(BUFFER_WIDTH));
  signal sReadPointer     : unsigned (log2ceil(BUFFER_WIDTH) - 1 downto 0) := to_unsigned(BUFFER_WIDTH - 1, log2ceil(BUFFER_WIDTH));
  signal sQuantityBits    : unsigned (log2ceil(BUFFER_WIDTH) downto 0); -- has to count up to BUFFER_SIZE
  signal sAxiHandshake    : boolean;
  signal sOutWordBuffer   : std_logic_vector(OUT_WIDTH - 1 downto 0);
  signal sWordValidBuffer : std_logic;
  signal sWriteBuffer     : std_logic;
  signal sWordToWrite     : std_logic_vector (LIMIT - 1 downto 0);
  signal sWordLen         : unsigned (log2ceil(LIMIT) downto 0);

begin

  sAxiHandshake <= (iReady and sWordValidBuffer) = '1';

  oWordValid      <= sWordValidBuffer;
  oWord           <= sOutWordBuffer;
  oBufferOverflow <= '1' when sQuantityBits > BUFFER_WIDTH else
    '0';

  process (iClk)
    variable vEncodedWord     : std_logic_vector (LIMIT - 1 downto 0);
    variable vFullLength      : natural;
    variable vSuffixLenInt    : natural;
    variable vWritePointerInt : integer;
    variable vReadPointerInt  : integer;
    variable vWrittenBits     : natural;
    variable vReadBits        : natural;
    variable vSliceWidthWr    : natural;
    variable vSliceWidthRd    : natural;
    variable vWordLenInt      : natural;

  begin

    if rising_edge(iClk) then

      if iRst = '1' then
        sWritePointer    <= to_unsigned(BUFFER_WIDTH - 1, sWritePointer'length);
        sReadPointer     <= to_unsigned(BUFFER_WIDTH - 1, sReadPointer'length);
        sQuantityBits    <= (others => '0');
        sBuffer          <= (others => '0');
        sOutWordBuffer   <= (others => '0');
        sWordValidBuffer <= '0';
        sWriteBuffer     <= '0';
        sWordLen         <= (others => '0');
        sWordToWrite     <= (others => '0');

      else

        ------------------------------------------------------------------------------------------------------------
        -- Write part
        ------------------------------------------------------------------------------------------------------------

        -- Default values
        vSuffixLenInt    := to_integer(iSuffixLen);
        vWritePointerInt := to_integer(sWritePointer);
        vReadPointerInt  := to_integer(sReadPointer);
        vEncodedWord     := (others => '0');
        vReadBits        := 0;
        vWrittenBits     := 0;
        sWriteBuffer <= iValid;
        vWordLenInt := to_integer(sWordLen);

        -- Build the word
        if iValid = '1' then
          vFullLength := to_integer(iUnaryZeros + 1 + iSuffixLen);

          -- Bit 1 to end unary zeros
          vEncodedWord(vSuffixLenInt downto 0) := '1' & std_logic_vector(resize(iSuffixVal, vSuffixLenInt));

          sWordToWrite <= vEncodedWord;
          sWordLen     <= to_unsigned(vFullLength, sWordLen'length);
        end if;

        -- Save the word
        if sWriteBuffer = '1' then
          -- Write to buffer
          if vWritePointerInt - vWordLenInt + 1 >= 0 then
            sBuffer(vWritePointerInt downto vWritePointerInt - vWordLenInt + 1) <= sWordToWrite(vWordLenInt - 1 downto 0);
          else
            -- sliced write
            vSliceWidthWr := vWordLenInt - vWritePointerInt - 1;
            sBuffer(vWritePointerInt downto 0)                            <= sWordToWrite(vWordLenInt - 1 downto vSliceWidthWr);
            sBuffer(BUFFER_WIDTH - 1 downto BUFFER_WIDTH - vSliceWidthWr) <= sWordToWrite(vSliceWidthWr - 1 downto 0);
          end if;

          vWritePointerInt := vWritePointerInt - vWordLenInt;
          if vWritePointerInt < 0 then
            vWritePointerInt := vWritePointerInt + BUFFER_WIDTH;
          end if;
          sWritePointer <= to_unsigned(vWritePointerInt, sWritePointer'length);

          vWrittenBits := vWordLenInt;
        end if;

        ------------------------------------------------------------------------------------------------------------
        -- Read part
        ------------------------------------------------------------------------------------------------------------

        if sQuantityBits >= OUT_WIDTH and (sAxiHandshake or sWordValidBuffer = '0') then
          if vReadPointerInt - OUT_WIDTH + 1 >= 0 then
            sOutWordBuffer <= sBuffer(vReadPointerInt downto vReadPointerInt - OUT_WIDTH + 1);
          else
            vSliceWidthRd := OUT_WIDTH - vReadPointerInt - 1;
            sOutWordBuffer(OUT_WIDTH - 1 downto vSliceWidthRd) <= sBuffer(vReadPointerInt downto 0);
            sOutWordBuffer(vSliceWidthRd - 1 downto 0)         <= sBuffer(BUFFER_WIDTH - 1 downto BUFFER_WIDTH - vSliceWidthRd);
          end if;

          sWordValidBuffer <= '1';
          vReadPointerInt := vReadPointerInt - OUT_WIDTH;
          if vReadPointerInt < 0 then
            vReadPointerInt := vReadPointerInt + BUFFER_WIDTH;
          end if;
          sReadPointer <= to_unsigned(vReadPointerInt, sReadPointer'length);

          vReadBits := OUT_WIDTH;
        elsif sQuantityBits < OUT_WIDTH and sAxiHandshake then
          sWordValidBuffer <= '0';
        end if;
        sQuantityBits <= sQuantityBits + vWrittenBits - vReadBits;

      end if;
    end if;
  end process;

end Behavioral;
