----------------------------------------------------------------------------------
-- Company:
-- Engineer:    Vitor Mendes Camilo
-- 
-- Create Date: 08/18/2025 09:27:13 PM
-- Design Name: 
-- Module Name: gradient_comp - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description:                         
--                                          
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:                 Code segment A.1
--                                      Local gradient computation for context determination
--
----------------------------------------------------------------------------------
use work.Common.all;

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity A1_gradient_comp is
  generic (
    BITNESS : natural range 8 to 16 := CO_BITNESS_STD
  );
  port (
    iA  : in unsigned (BITNESS - 1 downto 0);
    iB  : in unsigned (BITNESS - 1 downto 0);
    iC  : in unsigned (BITNESS - 1 downto 0);
    iD  : in unsigned (BITNESS - 1 downto 0);
    oD1 : out signed (BITNESS downto 0);
    oD2 : out signed (BITNESS downto 0);
    oD3 : out signed (BITNESS downto 0)
  );
end A1_gradient_comp;

architecture Behavioral of A1_gradient_comp is
begin

  oD1 <= signed('0' & iD) - signed('0' & iB);
  oD2 <= signed('0' & iB) - signed('0' & iC);
  oD3 <= signed('0' & iC) - signed('0' & iA);

end Behavioral;
