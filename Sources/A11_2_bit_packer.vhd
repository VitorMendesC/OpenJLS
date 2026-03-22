----------------------------------------------------------------------------------
-- Company:
-- Engineer:    Vitor Mendes Camilo
--
-- Create Date: 08/30/2025 07:55:00 PM
-- Module Name: A11_2_bit_packer - Behavioral
-- Description:
--
-- Notes:
--              Buffer is written from MSB to match the bitstream bit order.
--
--              Two independent write interfaces:
--
--                iRawValid   — appends iRawLen raw bits from iRawVal directly
--                              (no unary prefix, no terminating '1').
--                              Used for A.15 boundary '1' bits and A.16 break
--                              residual (residual value with leading '0').
--
--                iGolombValid — appends a Golomb-coded word:
--                              [iUnaryZeros zeros]['1'][iSuffixVal in iSuffixLen bits]
--                              Used for regular mode and run-interruption tokens.
--
--              If both valids are asserted on the same cycle, raw bits are
--              written first, Golomb code immediately after — one cycle later
--              (registered pipeline, same as single-input case).
--
--              iFlush: outputs whatever partial word remains in the buffer
--                      (< OUT_WIDTH bits), zero-padded at the LSB, then
--                      clears the bit count. No effect if buffer is empty.
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
    OUT_WIDTH       : natural := CO_BYTE_STUFFER_IN_WIDTH;
    BUFFER_WIDTH    : natural := CO_BUFFER_WIDTH_STD;
    UNARY_WIDTH     : natural := CO_UNARY_WIDTH_STD;
    SUFFIX_WIDTH    : natural := CO_SUFFIX_WIDTH_STD;
    SUFFIXLEN_WIDTH : natural := CO_SUFFIXLEN_WIDTH_STD
  );
  port (
    iClk  : in std_logic;
    iRst  : in std_logic;
    iFlush : in std_logic;
    -- Raw bits interface (A.15 boundary bits, A.16 break residual)
    iRawValid : in std_logic;
    iRawLen   : in unsigned(SUFFIXLEN_WIDTH - 1 downto 0);
    iRawVal   : in unsigned(SUFFIX_WIDTH - 1 downto 0);
    -- Golomb interface (regular mode, run-interruption)
    iGolombValid : in std_logic;
    iUnaryZeros  : in unsigned(UNARY_WIDTH - 1 downto 0);
    iSuffixLen   : in unsigned(SUFFIXLEN_WIDTH - 1 downto 0);
    iSuffixVal   : in unsigned(SUFFIX_WIDTH - 1 downto 0);
    -- Output (AXI-Stream)
    iReady          : in std_logic;
    oWord           : out std_logic_vector(OUT_WIDTH - 1 downto 0);
    oWordValid      : out std_logic;
    oBufferOverflow : out std_logic
  );
end A11_2_bit_packer;

architecture Behavioral of A11_2_bit_packer is

  signal sBuffer          : std_logic_vector(BUFFER_WIDTH - 1 downto 0);
  signal sWritePointer    : unsigned(log2ceil(BUFFER_WIDTH) - 1 downto 0) := to_unsigned(BUFFER_WIDTH - 1, log2ceil(BUFFER_WIDTH));
  signal sReadPointer     : unsigned(log2ceil(BUFFER_WIDTH) - 1 downto 0) := to_unsigned(BUFFER_WIDTH - 1, log2ceil(BUFFER_WIDTH));
  signal sQuantityBits    : unsigned(log2ceil(BUFFER_WIDTH) downto 0);
  signal sAxiHandshake    : boolean;
  signal sOutWordBuffer   : std_logic_vector(OUT_WIDTH - 1 downto 0);
  signal sWordValidBuffer : std_logic;

  -- Registered raw interface
  signal sRawBuffer  : std_logic;
  signal sRawToWrite : std_logic_vector(SUFFIX_WIDTH - 1 downto 0);
  signal sRawLen     : unsigned(SUFFIXLEN_WIDTH - 1 downto 0);

  -- Registered Golomb interface
  signal sGolombBuffer  : std_logic;
  signal sGolombToWrite : std_logic_vector(LIMIT - 1 downto 0);
  signal sGolombLen     : unsigned(log2ceil(LIMIT) downto 0);

begin

  sAxiHandshake <= (iReady and sWordValidBuffer) = '1';

  oWordValid      <= sWordValidBuffer;
  oWord           <= sOutWordBuffer;
  oBufferOverflow <= '1' when sQuantityBits > BUFFER_WIDTH else '0';

  process (iClk)
    variable vGolombWord     : std_logic_vector(LIMIT - 1 downto 0);
    variable vGolombLen      : natural;
    variable vSuffixLenInt   : natural;
    variable vRawLenInt      : natural;
    variable vGolombLenInt   : natural;
    variable vWritePointerInt : integer;
    variable vReadPointerInt  : integer;
    variable vWrittenBits    : natural;
    variable vReadBits       : natural;
    variable vSliceWidthWr   : natural;
    variable vSliceWidthRd   : natural;
    variable vQuantInt       : natural;
    variable vFlushWord      : std_logic_vector(OUT_WIDTH - 1 downto 0);
  begin

    if rising_edge(iClk) then

      if iRst = '1' then
        sWritePointer    <= to_unsigned(BUFFER_WIDTH - 1, sWritePointer'length);
        sReadPointer     <= to_unsigned(BUFFER_WIDTH - 1, sReadPointer'length);
        sQuantityBits    <= (others => '0');
        sBuffer          <= (others => '0');
        sOutWordBuffer   <= (others => '0');
        sWordValidBuffer <= '0';
        sRawBuffer       <= '0';
        sRawToWrite      <= (others => '0');
        sRawLen          <= (others => '0');
        sGolombBuffer    <= '0';
        sGolombToWrite   <= (others => '0');
        sGolombLen       <= (others => '0');

      else

        ----------------------------------------
        -- Write part
        ----------------------------------------

        vWritePointerInt := to_integer(sWritePointer);
        vReadPointerInt  := to_integer(sReadPointer);
        vWrittenBits     := 0;
        vReadBits        := 0;
        vRawLenInt       := to_integer(sRawLen);
        vGolombLenInt    := to_integer(sGolombLen);

        -- Register raw interface
        sRawBuffer <= iRawValid;
        if iRawValid = '1' then
          sRawToWrite <= std_logic_vector(resize(iRawVal, SUFFIX_WIDTH));
          sRawLen     <= iRawLen;
        end if;

        -- Register Golomb interface
        sGolombBuffer <= iGolombValid;
        if iGolombValid = '1' then
          vSuffixLenInt := to_integer(iSuffixLen);
          vGolombLen    := to_integer(iUnaryZeros + 1 + iSuffixLen);
          vGolombWord   := (others => '0');
          vGolombWord(vSuffixLenInt downto 0) := '1' & std_logic_vector(resize(iSuffixVal, vSuffixLenInt));
          sGolombToWrite <= vGolombWord;
          sGolombLen     <= to_unsigned(vGolombLen, sGolombLen'length);
        end if;

        -- Save: raw first (if present), then Golomb (if present)
        if sRawBuffer = '1' or sGolombBuffer = '1' then

          if sRawBuffer = '1' and vRawLenInt > 0 then
            if vWritePointerInt - vRawLenInt + 1 >= 0 then
              sBuffer(vWritePointerInt downto vWritePointerInt - vRawLenInt + 1) <= sRawToWrite(vRawLenInt - 1 downto 0);
            else
              vSliceWidthWr := vRawLenInt - vWritePointerInt - 1;
              sBuffer(vWritePointerInt downto 0)                             <= sRawToWrite(vRawLenInt - 1 downto vSliceWidthWr);
              sBuffer(BUFFER_WIDTH - 1 downto BUFFER_WIDTH - vSliceWidthWr) <= sRawToWrite(vSliceWidthWr - 1 downto 0);
            end if;
            vWritePointerInt := vWritePointerInt - vRawLenInt;
            if vWritePointerInt < 0 then
              vWritePointerInt := vWritePointerInt + BUFFER_WIDTH;
            end if;
            vWrittenBits := vRawLenInt;
          end if;

          if sGolombBuffer = '1' then
            if vWritePointerInt - vGolombLenInt + 1 >= 0 then
              sBuffer(vWritePointerInt downto vWritePointerInt - vGolombLenInt + 1) <= sGolombToWrite(vGolombLenInt - 1 downto 0);
            else
              vSliceWidthWr := vGolombLenInt - vWritePointerInt - 1;
              sBuffer(vWritePointerInt downto 0)                             <= sGolombToWrite(vGolombLenInt - 1 downto vSliceWidthWr);
              sBuffer(BUFFER_WIDTH - 1 downto BUFFER_WIDTH - vSliceWidthWr) <= sGolombToWrite(vSliceWidthWr - 1 downto 0);
            end if;
            vWritePointerInt := vWritePointerInt - vGolombLenInt;
            if vWritePointerInt < 0 then
              vWritePointerInt := vWritePointerInt + BUFFER_WIDTH;
            end if;
            vWrittenBits := vWrittenBits + vGolombLenInt;
          end if;

          sWritePointer <= to_unsigned(vWritePointerInt, sWritePointer'length);
        end if;

        ----------------------------------------
        -- Read part
        ----------------------------------------

        if sQuantityBits >= OUT_WIDTH and (sAxiHandshake or sWordValidBuffer = '0') then
          if vReadPointerInt - OUT_WIDTH + 1 >= 0 then
            sOutWordBuffer <= sBuffer(vReadPointerInt downto vReadPointerInt - OUT_WIDTH + 1);
          else
            vSliceWidthRd := OUT_WIDTH - vReadPointerInt - 1;
            sOutWordBuffer(OUT_WIDTH - 1 downto vSliceWidthRd) <= sBuffer(vReadPointerInt downto 0);
            sOutWordBuffer(vSliceWidthRd - 1 downto 0)         <= sBuffer(BUFFER_WIDTH - 1 downto BUFFER_WIDTH - vSliceWidthRd);
          end if;
          sWordValidBuffer <= '1';
          vReadPointerInt  := vReadPointerInt - OUT_WIDTH;
          if vReadPointerInt < 0 then
            vReadPointerInt := vReadPointerInt + BUFFER_WIDTH;
          end if;
          sReadPointer <= to_unsigned(vReadPointerInt, sReadPointer'length);
          vReadBits    := OUT_WIDTH;

        elsif iFlush = '1' and sQuantityBits > 0 and (sAxiHandshake or sWordValidBuffer = '0') then
          vQuantInt  := to_integer(sQuantityBits);
          vFlushWord := (others => '0');
          if vReadPointerInt - vQuantInt + 1 >= 0 then
            vFlushWord(OUT_WIDTH - 1 downto OUT_WIDTH - vQuantInt) := sBuffer(vReadPointerInt downto vReadPointerInt - vQuantInt + 1);
          else
            vSliceWidthRd                                                            := vQuantInt - vReadPointerInt - 1;
            vFlushWord(OUT_WIDTH - 1 downto OUT_WIDTH - vReadPointerInt - 1)         := sBuffer(vReadPointerInt downto 0);
            vFlushWord(OUT_WIDTH - vReadPointerInt - 2 downto OUT_WIDTH - vQuantInt) := sBuffer(BUFFER_WIDTH - 1 downto BUFFER_WIDTH - vSliceWidthRd);
          end if;
          sOutWordBuffer   <= vFlushWord;
          sWordValidBuffer <= '1';
          vReadPointerInt  := vReadPointerInt - vQuantInt;
          if vReadPointerInt < 0 then
            vReadPointerInt := vReadPointerInt + BUFFER_WIDTH;
          end if;
          sReadPointer <= to_unsigned(vReadPointerInt, sReadPointer'length);
          vReadBits    := vQuantInt;

        elsif sQuantityBits < OUT_WIDTH and sAxiHandshake then
          sWordValidBuffer <= '0';
        end if;

        sQuantityBits <= sQuantityBits + vWrittenBits - vReadBits;

      end if;
    end if;
  end process;

end Behavioral;
