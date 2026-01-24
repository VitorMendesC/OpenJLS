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

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use work.Common.all;

entity A9_modulo_reduction is
  generic (
    BITNESS : natural range 8 to 16 := 12
  );
  port (
    iErrorValue : in signed (BITNESS downto 0);
    oErrorValue : out signed (BITNESS downto 0)
  );
end A9_modulo_reduction;

architecture Behavioral of A9_modulo_reduction is
  constant MAX_VAL : natural := 2 ** (BITNESS) - 1;
  constant C_RANGE : natural := MAX_VAL + 1;
  signal sErrAdj   : signed (BITNESS downto 0);
begin

  -- First stage: if negative, add RANGE
  sErrAdj <= iErrorValue + C_RANGE when iErrorValue < 0 else
    iErrorValue;

  -- Second stage: if >= (RANGE + 1)/2, subtract RANGE
  oErrorValue <= sErrAdj - C_RANGE when sErrAdj >= (C_RANGE + 1) / 2 else
    sErrAdj;

end Behavioral;
