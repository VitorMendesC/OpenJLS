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
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use work.Common.all;

entity A11_1_golomb_encoder is
  generic (
    BITNESS                : natural := CO_BITNESS_STD; -- TODO: Why is this here?
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
begin

  -- Implements the Limited-Length Golomb code LG(k, LIMIT) as per T.87 A.5.3
  -- Metadata output:
  --   - oUnaryZeros: q (or LIMIT-QBPP-1 in escape)
  --   - oSuffixLen: k (or QBPP in escape)
  --   - oSuffixVal: r (or MErrval-1 in escape), aligned LSB
  --   - oTotalLen : unaryZeros + 1 + suffixLen
  --   - oIsEscape : '1' when q >= LIMIT - QBPP - 1
  process (iK, iMappedErrorVal)
    variable vLen        : integer;
    variable vK          : integer;
    variable vM          : integer;
    variable vQ          : integer; -- quotient (high-order bits of MErrval)
    variable vThresh     : integer; -- LIMIT - qbpp - 1
    variable uM          : unsigned(iMappedErrorVal'range);
    variable uR          : unsigned(iMappedErrorVal'range);
    variable uTmp        : unsigned(iMappedErrorVal'range);
    variable vUnaryZeros : integer;
    variable vSuffixLen  : integer;
    variable vIsEscape   : boolean;
    variable vSuffixVal  : unsigned(SUFFIX_WIDTH - 1 downto 0);
  begin

    vK := to_integer(iK);
    vM := to_integer(iMappedErrorVal);
    uM := iMappedErrorVal;
    -- q = high-order bits of MErrval = floor(MErrval / 2^k)
    vQ := to_integer(shift_right(uM, vK));
    -- r = low k bits of MErrval = MErrval - (q << k)
    uR      := uM - shift_left(shift_right(uM, vK), vK);
    vThresh := integer(LIMIT) - integer(QBPP) - 1;

    vIsEscape := (vQ >= vThresh);

    if not vIsEscape then
      vUnaryZeros := vQ;
      vSuffixLen  := vK;
      vLen        := vUnaryZeros + 1 + vSuffixLen;
      vSuffixVal  := (others => '0');

      if vK > 0 then
        vSuffixVal(vK - 1 downto 0) := uR(vK - 1 downto 0);
      end if;

    else
      vUnaryZeros := vThresh;
      vSuffixLen  := integer(QBPP);
      vLen        := integer(LIMIT);

      if vM > 0 then
        uTmp := to_unsigned(vM - 1, uTmp'length);
      else
        uTmp := (others => '0');
      end if;

      vSuffixVal := (others => '0');
      if QBPP > 0 then
        vSuffixVal(QBPP - 1 downto 0) := uTmp(QBPP - 1 downto 0);
      end if;
    end if;

    oUnaryZeros <= to_unsigned(vUnaryZeros, oUnaryZeros'length);
    oSuffixLen  <= to_unsigned(vSuffixLen, oSuffixLen'length);
    oSuffixVal  <= resize(vSuffixVal, oSuffixVal'length);
    oTotalLen   <= to_unsigned(vLen, oTotalLen'length);
    if vIsEscape then
      oIsEscape <= '1';
    else
      oIsEscape <= '0';
    end if;

  end process;
end Behavioral;
