----------------------------------------------------------------------------------
-- Company:
-- Engineer:    Vitor Mendes Camilo
-- 
-- Create Date: 08/30/2025 11:32:34 AM
-- Design Name: 
-- Module Name: A11_1_golomb_encoder - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:             Code segment A11.1
--                                  Not actual segment, described in text
--                                  on A.5.3
--
--
-- Assumptions:
--              (1) k <= SUFFIX_WIDTH       and     k   <= MAPPED_ERROR_VAL_WIDTH
--              (2) QBPP <= SUFFIX_WIDTH    and     QBPP <= MAPPED_ERROR_VAL_WIDTH
--
----------------------------------------------------------------------------------

use work.Common.all;

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity A11_1_golomb_encoder is
  generic (
    K_WIDTH                : natural := CO_K_WIDTH_STD;
    QBPP                   : natural := CO_QBPP_STD;
    LIMIT                  : natural := CO_LIMIT_STD;
    UNARY_WIDTH            : natural := CO_UNARY_WIDTH_STD;
    SUFFIX_WIDTH           : natural := CO_SUFFIX_WIDTH_STD;
    SUFFIXLEN_WIDTH        : natural := CO_SUFFIXLEN_WIDTH_STD;
    TOTLEN_WIDTH           : natural := CO_TOTLEN_WIDTH_STD;
    MAPPED_ERROR_VAL_WIDTH : natural := CO_MAPPED_ERROR_VAL_WIDTH_STD
  );
  port (
    iK              : in unsigned (K_WIDTH - 1 downto 0);
    iMappedErrorVal : in unsigned (MAPPED_ERROR_VAL_WIDTH - 1 downto 0);
    oUnaryZeros     : out unsigned (UNARY_WIDTH - 1 downto 0);
    oSuffixLen      : out unsigned (SUFFIXLEN_WIDTH - 1 downto 0);
    oSuffixVal      : out unsigned (SUFFIX_WIDTH - 1 downto 0);
    oTotalLen       : out unsigned (TOTLEN_WIDTH - 1 downto 0);
    oIsEscape       : out std_logic
  );
end A11_1_golomb_encoder;

architecture Behavioral of A11_1_golomb_encoder is
  constant THRESHOLD : natural := LIMIT - QBPP - 1;

begin

  -- Implements the Limited-Length Golomb code LG(k, LIMIT) as per T.87 A.5.3
  -- Metadata output:
  --   - oUnaryZeros: q (or LIMIT-QBPP-1 in escape)
  --   - oSuffixLen: k (or QBPP in escape)
  --   - oSuffixVal: r (or MErrval-1 in escape), aligned LSB
  --   - oTotalLen : unaryZeros + 1 + suffixLen
  --   - oIsEscape : '1' when q >= LIMIT - QBPP - 1
  process (iK, iMappedErrorVal)
    variable vLen            : unsigned(oTotalLen'range);
    variable vKInt           : integer;
    variable vHighOrder      : unsigned(iMappedErrorVal'range);
    variable vLowOrder       : unsigned(iMappedErrorVal'range);
    variable vMappedErrorDec : unsigned(iMappedErrorVal'range);
    variable vUnaryZeros     : unsigned(oUnaryZeros'range);
    variable vSuffixLen      : unsigned(oSuffixLen'range);
    variable vIsEscape       : boolean;
    variable vSuffixVal      : unsigned(SUFFIX_WIDTH - 1 downto 0);
  begin

    vKInt := to_integer(iK);
    -- q = high-order bits of MErrval = floor(MErrval / 2^k)
    vHighOrder := shift_right(iMappedErrorVal, vKInt);
    -- r = low k bits of MErrval = MErrval - (q << k)
    vLowOrder := iMappedErrorVal - shift_left(shift_right(iMappedErrorVal, vKInt), vKInt);

    vIsEscape := (vHighOrder >= THRESHOLD);

    if not vIsEscape then
      vUnaryZeros := resize(vHighOrder, vUnaryZeros'length);
      vSuffixLen  := resize(iK, vSuffixLen'length);
      vLen        := vUnaryZeros + 1 + vSuffixLen;

      vSuffixVal := resize(vLowOrder, vSuffixVal'length);

    else
      -- SIM ONLY ------------------------------------------------------------------
      assert (iMappedErrorVal /= 0) -- Catch impossible case on simulation set
      report "LG(k,LIMIT) escape with MErrval=0 is impossible per T.87/14495-1"
        severity failure;
      ------------------------------------------------------------------------------

      vUnaryZeros := to_unsigned(THRESHOLD, vUnaryZeros'length);
      vSuffixLen  := to_unsigned(QBPP, vSuffixLen'length);
      vLen        := to_unsigned(LIMIT, vLen'length);

      vMappedErrorDec := iMappedErrorVal - 1; -- MErrval is guaranteed to be greater than 1 when escape

      vSuffixVal                    := (others => '0');
      vSuffixVal(QBPP - 1 downto 0) := vMappedErrorDec(QBPP - 1 downto 0);
    end if;

    oUnaryZeros <= vUnaryZeros;
    oSuffixLen  <= vSuffixLen;
    oSuffixVal  <= vSuffixVal;
    oTotalLen   <= vLen;

    if vIsEscape then
      oIsEscape <= '1';
    else
      oIsEscape <= '0';
    end if;

  end process;
end Behavioral;
