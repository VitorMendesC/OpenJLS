----------------------------------------------------------------------------------
-- Company:
-- Engineer:    Vitor Mendes Camilo
--
-- Create Date: 02/07/2026
-- Design Name:
-- Module Name: A18_run_interruption_prediction_error - Behavioral
-- Project Name:
-- Target Devices:
-- Tool Versions:
-- Description:
--
-- Dependencies:
--
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:                 Code segment A.18
--                                      Prediction error for a run interruption sample
--
----------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.common.all;

entity a18_run_interruption_prediction_error is
  generic (
    BITNESS : natural range 8 to 16 := CO_BITNESS_STD
  );
  port (
    iRItype : in    std_logic;
    iRa     : in    unsigned (BITNESS - 1 downto 0);
    iRb     : in    unsigned (BITNESS - 1 downto 0);
    iIx     : in    unsigned (BITNESS - 1 downto 0);
    oErrval : out   signed (BITNESS downto 0)
  );
end entity a18_run_interruption_prediction_error;

architecture behavioral of a18_run_interruption_prediction_error is

  signal sPx : unsigned (BITNESS - 1 downto 0);

begin

  sPx <= iRa when iRItype = '1' else
         iRb;

  oErrval <= signed('0' & iIx) - signed('0' & sPx);

end architecture behavioral;
