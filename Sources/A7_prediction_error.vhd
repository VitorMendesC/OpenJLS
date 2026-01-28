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

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use work.Common.all;

entity A7_prediction_error is
  generic (
    BITNESS : natural range 8 to 16 := CO_BITNESS_STD
  );
  port (
    iIx         : in unsigned (BITNESS - 1 downto 0);
    iPx         : in unsigned (BITNESS - 1 downto 0);
    iSign       : in std_logic; -- '1' for SIGN = -1
    oErrorValue : out signed (BITNESS downto 0)
  );
end A7_prediction_error;

architecture Behavioral of A7_prediction_error is
begin

  oErrorValue <= signed('0' & iIx) - signed('0' & iPx) when iSign = '0'
    else
    signed('0' & iPx) - signed('0' & iIx);

end Behavioral;
