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
    BITNESS : natural range 8 to 16 := 12;
    MAX_VAL : natural               := 2 ** (BITNESS) - 1;
    C_RANGE : natural               := MAX_VAL + 1
  );
  port (
    iErrorValue : in signed (BITNESS downto 0);
    oErrorValue : out signed (BITNESS downto 0)
  );
end A9_modulo_reduction;

architecture Behavioral of A9_modulo_reduction is
begin

  -- Combinational modulo reduction
  oErrorValue <= iErrorValue + C_RANGE when iErrorValue < 0 else
    iErrorValue - C_RANGE when iErrorValue >= (C_RANGE + 1)/2 else
    iErrorValue;

end Behavioral;
