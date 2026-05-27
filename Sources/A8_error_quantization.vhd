----------------------------------------------------------------------------------
  -- Company:
  -- Engineer:    Vitor Mendes Camilo
  --
  -- Create Date: 02/07/2026
  -- Design Name:
  -- Module Name: A8_error_quantization - Behavioral
  -- Project Name:
  -- Target Devices:
  -- Tool Versions:
  -- Description:
  --
  -- Dependencies:
  --
  -- Revision:
  -- Revision 0.01 - File Created
  -- Additional Comments:                 Code segment A.8
  --                                      Error quantization and computation of the
  --                                      reconstructed value in near-lossless coding
  --
  -- "In lossless coding (NEAR = 0), the reconstructed value Rx shall be set to Ix."
  -- T.87, pg. 20
  ----------------------------------------------------------------------------------
  use work.common.all;

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity a8_error_quantization is
  generic (
    BITNESS : natural range 8 to 16 := CO_BITNESS_STD;
    MAX_VAL : natural               := CO_MAX_VAL_STD
  );
  port (
    iErrorVal : in    signed (BITNESS downto 0);
    iPx       : in    unsigned (BITNESS - 1 downto 0);
    iSign     : in    std_logic;
    oRx       : out   unsigned (BITNESS - 1 downto 0)
  );
end entity a8_error_quantization;

architecture behavioral of a8_error_quantization is

begin

  p_error_quant : process (iErrorVal, iPx, iSign) is

    variable vErrInt   : integer;
    variable vRx       : integer;
    variable vSignMult : integer;

  begin

    if (iSign = CO_SIGN_POS) then
      vSignMult := 1;
    else
      vSignMult := - 1;
    end if;

    vErrInt := to_integer(iErrorVal);
    vRx     := to_integer(iPx) + vSignMult * vErrInt;

    if (vRx < 0) then
      vRx := 0;
    elsif (vRx > MAX_VAL) then
      vRx := MAX_VAL;
    end if;

    oRx <= to_unsigned(vRx, oRx'length);

  end process p_error_quant;

end architecture behavioral;
