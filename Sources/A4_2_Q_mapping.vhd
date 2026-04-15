----------------------------------------------------------------------------------
-- Company:
-- Engineer:    Vitor Mendes Camilo
-- 
-- Create Date: 08/30/2025 06:46:04 PM
-- Design Name: 
-- Module Name: A4_2_Q_mapping - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:             Written requirement A.4.2 - Merge quantized vector into Q
-- 
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity A4_2_Q_mapping is
  port (
    iQ1 : in signed(3 downto 0);   -- [0, 4]
    iQ2 : in signed(3 downto 0);   -- [-4, 4]
    iQ3 : in signed(3 downto 0);   -- [-4, 4]
    oQ  : out unsigned(8 downto 0) -- [0..364]
  );
end A4_2_Q_mapping;

architecture Behavioral of A4_2_Q_mapping is
  -- Q = 81*Q1 + 9*Q2 + Q3  (Mert, 2018)
  signal sQ1 : unsigned(2 downto 0);
  signal s81 : unsigned(8 downto 0); -- 81*Q1,  [0..324]
  signal s9  : signed(7 downto 0);   -- 9*Q2,  [-72..72]
begin

  sQ1 <= unsigned(iQ1(2 downto 0)); -- Q1 is in range [0..4]

  s81 <= shift_left(resize(sQ1, 9), 6)
    or shift_left(resize(sQ1, 9), 4)
    or resize(sQ1, 9);

  s9 <= shift_left(resize(iQ2, 8), 3)
     + resize(iQ2, 8);

  oQ <= resize(unsigned(signed('0' & s81) + s9 + iQ3), 9);
end Behavioral;
