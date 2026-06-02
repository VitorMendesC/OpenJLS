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

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.std_logic_misc.all;
  use work.common.all;

entity a3_mode_selection is
  generic (
    BITNESS  : natural range 8 to 16 := CO_BITNESS_STD
  );
  port (
    iD1      : in    signed(BITNESS downto 0); -- signed
    iD2      : in    signed(BITNESS downto 0);
    iD3      : in    signed(BITNESS downto 0);
    oModeRun : out   std_logic
  );
end entity a3_mode_selection;

architecture behavioral of a3_mode_selection is

begin

  oModeRun <= '1' when or_reduce(std_logic_vector(iD1 or iD2 or iD3)) = '0' else
              '0';

end architecture behavioral;
