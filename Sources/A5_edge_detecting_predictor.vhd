----------------------------------------------------------------------------------
-- Company:
-- Engineer:    Vitor Mendes Camilo
--
-- Create Date: 08/23/2025 11:28:03 PM
-- Design Name:
-- Module Name: edge_detecting_predictor - Behavioral
-- Project Name:
-- Target Devices:
-- Tool Versions:
-- Description:
--
-- Dependencies:
--
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:             Code segment A.5
--                                  Edge-detecting predictor
--
----------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.common.all;

entity a5_edge_detecting_predictor is
  generic (
    BITNESS : natural range 8 to 16 := CO_BITNESS_STD
  );
  port (
    iA  : in    unsigned (BITNESS - 1 downto 0);
    iB  : in    unsigned (BITNESS - 1 downto 0);
    iC  : in    unsigned (BITNESS - 1 downto 0);
    oPx : out   unsigned (BITNESS - 1 downto 0)
  );
end entity a5_edge_detecting_predictor;

architecture behavioral of a5_edge_detecting_predictor is

begin

  oPx <= math_min(iA, iB) when iC >= math_max(iA, iB) else
         math_max(iA, iB) when iC <= math_min(iA, iB) else
         iA + iB - iC;

end architecture behavioral;
