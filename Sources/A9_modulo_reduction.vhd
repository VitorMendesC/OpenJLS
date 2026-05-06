----------------------------------------------------------------------------------
-- Company:
-- Engineer:    Vitor Mendes Camilo
-- 
-- Create Date: 08/29/2025 10:53:41 PM
-- Design Name: 
-- Module Name: A9_modulo_reduction - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:                 Code segment A.9
--                                      Modulo reduction of the error
-- 
----------------------------------------------------------------------------------

use work.Common.all;

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity A9_modulo_reduction is
  generic (
    BITNESS : natural range 8 to 16 := CO_BITNESS_STD;
    RANGE_P : natural               := CO_RANGE_STD
  );
  port (
    iErrorVal : in signed (BITNESS downto 0);
    oErrorVal : out signed (BITNESS downto 0)
  );
end A9_modulo_reduction;

architecture Behavioral of A9_modulo_reduction is
  -- Intermediate widened by one bit so RANGE_P fits without sign-bit roll.
  -- Required for any BITNESS: RANGE_P = 2**BITNESS, so signed(BITNESS+2) gives
  -- max = 2**(BITNESS+1) - 1 >= RANGE_P.
  constant RANGE_S : signed(BITNESS + 1 downto 0) := to_signed(RANGE_P, BITNESS + 2);

  signal sExt    : signed(BITNESS + 1 downto 0);
  signal sErrAdj : signed(BITNESS + 1 downto 0);
begin

  sExt <= resize(iErrorVal, BITNESS + 2);

  sErrAdj <= sExt + RANGE_S when iErrorVal < 0 else
    sExt;

  oErrorVal <= resize(sErrAdj - RANGE_S, BITNESS + 1) when sErrAdj >= (RANGE_P + 1) / 2 else
    resize(sErrAdj, BITNESS + 1);

end Behavioral;
