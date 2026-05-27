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

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.common.all;

entity a17_run_interruption_index is
  generic (
    BITNESS : natural range 8 to 16 := CO_BITNESS_STD
  );
  port (
    iRa     : in    unsigned (BITNESS - 1 downto 0);
    iRb     : in    unsigned (BITNESS - 1 downto 0);
    oRItype : out   std_logic
  );
end entity a17_run_interruption_index;

architecture behavioral of a17_run_interruption_index is

begin

  oRItype <= '1' when iRa = iRb else
             '0';

end architecture behavioral;
