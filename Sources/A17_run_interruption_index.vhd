----------------------------------------------------------------------------------
-- Company:
-- Engineer:    Vitor Mendes Camilo
-- 
-- Create Date: 02/07/2026
-- Design Name: 
-- Module Name: A17_run_interruption_index - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:                 Code segment A.17
--                                      Index computation for run interruption
-- 
----------------------------------------------------------------------------------

use work.Common.all;

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity A17_run_interruption_index is
  generic (
    BITNESS : natural range 8 to 16 := CO_BITNESS_STD
  );
  port (
    iRa     : in unsigned (BITNESS - 1 downto 0);
    iRb     : in unsigned (BITNESS - 1 downto 0);
    oRItype : out std_logic
  );
end A17_run_interruption_index;

architecture Behavioral of A17_run_interruption_index is
begin

  oRItype <= '1' when iRa = iRb else
    '0';

end Behavioral;
