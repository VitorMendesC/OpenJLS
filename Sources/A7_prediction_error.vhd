----------------------------------------------------------------------------------
-- Company:
-- Engineer:    Vitor Mendes Camilo
--
-- Create Date: 08/24/2025 03:24:03 PM
-- Design Name:
-- Module Name: prediction_error - Behavioral
-- Project Name:
-- Target Devices:
-- Tool Versions:
-- Description:
--
-- Dependencies:
--
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:             Code segment A.7
--                                  Computation of prediction error
--
----------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.common.all;

entity a7_prediction_error is
  generic (
    BITNESS : natural range 8 to 16 := CO_BITNESS_STD
  );
  port (
    iIx       : in    unsigned (BITNESS - 1 downto 0);
    iPx       : in    unsigned (BITNESS - 1 downto 0);
    iSign     : in    std_logic;
    oErrorVal : out   signed (BITNESS downto 0)
  );
end entity a7_prediction_error;

architecture behavioral of a7_prediction_error is

begin

  oErrorVal <= signed('0' & iIx) - signed('0' & iPx) when iSign = CO_SIGN_POS else
               signed('0' & iPx) - signed('0' & iIx);

end architecture behavioral;
