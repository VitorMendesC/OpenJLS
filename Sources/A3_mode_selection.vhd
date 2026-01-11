----------------------------------------------------------------------------------
-- Company:
-- Engineer:    Vitor Mendes Camilo
-- 
-- Create Date: 08/18/2025 10:04:45 PM
-- Design Name: 
-- Module Name: mode_selection - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description:                        
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:                 Code segment A.3
--                                      Local gradient computation for context determination
-- 
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity A3_mode_selection is
  generic (
    BITNESS : natural range 8 to 16 := 12
  );
  port (
    iD1          : in signed(BITNESS downto 0); -- signed
    iD2          : in signed(BITNESS downto 0);
    iD3          : in signed(BITNESS downto 0);
    oModeRegular : out std_logic;
    oModeRun     : out std_logic
  );
end A3_mode_selection;

architecture Behavioral of A3_mode_selection is
  constant cZeroVect : std_logic_vector (BITNESS downto 0) := (others => '0');
  signal sModeRun    : std_logic;
begin

  sModeRun <= '1' when std_logic_vector(iD1 or iD2 or iD3) = cZeroVect else
    '0';
  oModeRun     <= sModeRun;
  oModeRegular <= not sModeRun;

end Behavioral;
