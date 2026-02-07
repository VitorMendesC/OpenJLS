----------------------------------------------------------------------------------
-- Company:
-- Engineer:    Vitor Mendes Camilo
-- 
-- Create Date: 02/07/2026
-- Design Name: 
-- Module Name: A2_mode_selection - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:                 Code segment A.2
-- 
----------------------------------------------------------------------------------

use work.Common.all;

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity A2_mode_selection is
  generic (
    BITNESS : natural range 8 to 16 := CO_BITNESS_STD;
    NEAR    : natural               := CO_NEAR_STD
  );
  port (
    iD1          : in signed(BITNESS downto 0);
    iD2          : in signed(BITNESS downto 0);
    iD3          : in signed(BITNESS downto 0);
    oModeRegular : out std_logic;
    oModeRun     : out std_logic
  );
end A2_mode_selection;

architecture Behavioral of A2_mode_selection is
  signal sModeRun : std_logic;
  constant C_NEAR : signed(BITNESS downto 0) := to_signed(NEAR, BITNESS + 1);
begin

  sModeRun <= '1' when (abs(iD1) <= C_NEAR and abs(iD2) <= C_NEAR and abs(iD3) <= C_NEAR) else
    '0';

  oModeRun     <= sModeRun;
  oModeRegular <= not sModeRun;

end Behavioral;
