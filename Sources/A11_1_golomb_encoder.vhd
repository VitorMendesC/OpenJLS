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
    MAPPED_ERROR_VAL_WIDTH : natural := CO_MAPPED_ERROR_VAL_WIDTH_STD
  );
  port (
    iK              : in unsigned (K_WIDTH - 1 downto 0);
    iMappedErrorVal : in unsigned (MAPPED_ERROR_VAL_WIDTH - 1 downto 0);
    -- iRiMode selects T.87 A.22.1 LG(k, glimit) with glimit = LIMIT - J[iRunIndex] - 1.
    -- iRunIndex is the RUNindex value before the A.16 decrement. Ignored when iRiMode='0'.
    iRiMode     : in std_logic;
    iRunIndex   : in unsigned (4 downto 0);
    oUnaryZeros : out unsigned (UNARY_WIDTH - 1 downto 0);
    oSuffixLen  : out unsigned (SUFFIXLEN_WIDTH - 1 downto 0);
    oSuffixVal  : out unsigned (SUFFIX_WIDTH - 1 downto 0)
  );
end A11_1_golomb_encoder;

architecture Behavioral of A11_1_golomb_encoder is
  constant REG_THRESHOLD : natural := LIMIT - QBPP - 1;

begin

  -- Limited-Length Golomb LG(k, L). L=LIMIT in regular mode (A.5.3) and
  -- L=glimit=LIMIT-J[iRunIndex]-1 in RI mode (A.22.1). Non-escape if
  -- high_order < L - QBPP - 1. Escape emits (L - QBPP - 1) zeros + '1' + QBPP
  -- bits of (MErrval - 1); total escape length = L, so RI prefix + code = LIMIT.
  process (iK, iMappedErrorVal, iRiMode, iRunIndex)
    variable vKInt           : integer;
    variable vHighOrder      : unsigned(iMappedErrorVal'range);
    variable vLowOrder       : unsigned(iMappedErrorVal'range);
    variable vMappedErrorDec : unsigned(iMappedErrorVal'range);
    variable vUnaryZeros     : unsigned(oUnaryZeros'range);
    variable vSuffixLen      : unsigned(oSuffixLen'range);
    variable vIsEscape       : boolean;
    variable vSuffixVal      : unsigned(oSuffixVal'range);
    variable vJ              : natural;
    variable vThreshold      : natural;
  begin

    if iRiMode = '1' then
      vJ         := CO_J_TABLE(to_integer(iRunIndex));
      vThreshold := LIMIT - vJ - QBPP - 2;
    else
      vThreshold := REG_THRESHOLD;
    end if;

    vKInt := to_integer(iK);
    -- q = high-order bits of MErrval = floor(MErrval / 2^k)
    vHighOrder := shift_right(iMappedErrorVal, vKInt);
    -- r = low k bits of MErrval = MErrval - (q << k)
    vLowOrder := iMappedErrorVal - shift_left(vHighOrder, vKInt);

    vIsEscape := (vHighOrder >= vThreshold);

    if not vIsEscape then
      vUnaryZeros := resize(vHighOrder, vUnaryZeros'length);
      vSuffixLen  := resize(iK, vSuffixLen'length);

      vSuffixVal := resize(vLowOrder, vSuffixVal'length);

    else

      -- TODO: Remove after verification
      -- SIM ONLY ------------------------------------------------------------------
      assert (iMappedErrorVal /= 0) -- Catch impossible case on simulation set
      report "LG(k,LIMIT) escape with MErrval=0 is impossible per T.87/14495-1"
        severity failure;
      ------------------------------------------------------------------------------

      vUnaryZeros := to_unsigned(vThreshold, vUnaryZeros'length);
      vSuffixLen  := to_unsigned(QBPP, vSuffixLen'length);

      vMappedErrorDec := iMappedErrorVal - 1; -- MErrval is guaranteed to be greater than 1 when escape

      vSuffixVal                    := (others => '0');
      vSuffixVal(QBPP - 1 downto 0) := vMappedErrorDec(QBPP - 1 downto 0);
    end if;

    oUnaryZeros <= vUnaryZeros;
    oSuffixLen  <= vSuffixLen;
    oSuffixVal  <= vSuffixVal;

  end process;
end Behavioral;
