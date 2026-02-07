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

use work.Common.all;

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity A8_error_quantization is
  generic (
    BITNESS : natural range 8 to 16 := CO_BITNESS_STD;
    MAX_VAL : natural               := CO_MAX_VAL_STD;
    NEAR    : natural               := CO_NEAR_STD
  );
  port (
    iErrorVal : in signed (BITNESS downto 0);
    iPx       : in unsigned (BITNESS - 1 downto 0);
    iSign     : in std_logic;
    oErrorVal : out signed (BITNESS downto 0);
    oRx       : out unsigned (BITNESS - 1 downto 0)
  );
end A8_error_quantization;

architecture Behavioral of A8_error_quantization is
  constant C_SCALE : integer := (2 * NEAR) + 1;

begin

  process (iErrorVal, iPx, iSign)
    variable vErr       : integer;
    variable vErrUpdate : integer;
    variable vRx        : integer;
    variable vSignMult  : integer;
  begin
    vErr := to_integer(iErrorVal);

    -- Guarantees positive division
    if vErr > 0 then
      vErrUpdate := (vErr + NEAR) / C_SCALE;
    else
      vErrUpdate := - ((NEAR - vErr) / C_SCALE); -- divide positive, then negate
    end if;

    if iSign = CO_SIGN_POS then
      vSignMult := 1;
    else
      vSignMult := - 1;
    end if;

    vRx := to_integer(iPx) + vSignMult * vErrUpdate * C_SCALE;

    if vRx < 0 then
      vRx := 0;
    elsif vRx > MAX_VAL then
      vRx := MAX_VAL;
    end if;

    oErrorVal <= to_signed(vErrUpdate, oErrorVal'length);
    oRx       <= to_unsigned(vRx, oRx'length);
  end process;

end Behavioral;
