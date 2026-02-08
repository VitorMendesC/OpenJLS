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

use work.Common.all;

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity A18_run_interruption_prediction_error is
  generic (
    BITNESS : natural range 8 to 16 := CO_BITNESS_STD
  );
  port (
    iRItype  : in std_logic;
    iRa      : in unsigned (BITNESS - 1 downto 0);
    iRb      : in unsigned (BITNESS - 1 downto 0);
    iIx      : in unsigned (BITNESS - 1 downto 0);
    oPx      : out unsigned (BITNESS - 1 downto 0);
    oErrval  : out signed (BITNESS downto 0)
  );
end A18_run_interruption_prediction_error;

architecture Behavioral of A18_run_interruption_prediction_error is
  signal sPx : unsigned (BITNESS - 1 downto 0);

begin

  sPx <= iRa when iRItype = '1' else
    iRb;

  oPx     <= sPx;
  oErrval <= signed('0' & iIx) - signed('0' & sPx);

end Behavioral;
