----------------------------------------------------------------------------------
-- Company:
-- Engineer:    Vitor Mendes Camilo
-- 
-- Create Date: 02/07/2026
-- Design Name: 
-- Module Name: A20_compute_temp - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:                 Code segment A.20
--                                      Computation of the auxiliary variable TEMP
-- 
----------------------------------------------------------------------------------

use work.Common.all;

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity A20_compute_temp is
  generic (
    A_WIDTH : natural := CO_AQ_WIDTH_STD;
    N_WIDTH : natural := CO_NQ_WIDTH_STD
  );
  port (
    iRItype : in std_logic;
    iA365   : in unsigned (A_WIDTH - 1 downto 0);
    iA366   : in unsigned (A_WIDTH - 1 downto 0);
    iN366   : in unsigned (N_WIDTH - 1 downto 0);
    oTemp   : out unsigned (A_WIDTH - 1 downto 0)
  );
end A20_compute_temp;

architecture Behavioral of A20_compute_temp is
begin

  process (iRItype, iA365, iA366, iN366)
    variable vTemp : unsigned (A_WIDTH - 1 downto 0);
  begin
    if iRItype = '0' then
      vTemp := iA365;
    else
      vTemp := iA366 + resize(shift_right(iN366, 1), vTemp'length);
    end if;

    oTemp <= vTemp;
  end process;

end Behavioral;
