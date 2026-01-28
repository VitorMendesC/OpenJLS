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

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use work.Common.all;

entity A5_edge_detecting_predictor is
  generic (
    BITNESS : natural range 8 to 16 := CO_BITNESS_STD
  );
  port (
    iA  : in unsigned (BITNESS - 1 downto 0);
    iB  : in unsigned (BITNESS - 1 downto 0);
    iC  : in unsigned (BITNESS - 1 downto 0);
    oPx : out unsigned (BITNESS - 1 downto 0)
  );
end A5_edge_detecting_predictor;

architecture Behavioral of A5_edge_detecting_predictor is
begin

  oPx                     <= minimum(iA, iB) when iC >= maximum(iA, iB) else
    maximum(iA, iB) when iC <= minimum(iA, iB) else
    iA + iB - iC;

end Behavioral;
