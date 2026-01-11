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
-- Additional Comments:             Code segment A.4.2
--                                  Not actual code segment
--                                  Described in section A.3.4
-- 
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity A4_2_Q_mapping is
  port (
    iQ1 : in signed(3 downto 0); -- range [-4, 4]
    iQ2 : in signed(3 downto 0);
    iQ3 : in signed(3 downto 0);
    oQ  : out unsigned(8 downto 0) -- 0..364 fits in 9 bits
  );
end A4_2_Q_mapping;

architecture Behavioral of A4_2_Q_mapping is
begin
  -- CharLS-style one-to-one mapping from (Q1,Q2,Q3) -> Q in [0..364]
  -- Assumes inputs are already merged per A.4.1: Q1 >= 0; if Q1==0 then Q2>=0; if Q1==0 and Q2==0 then Q3>=0
  process (iQ1, iQ2, iQ3)
    variable vQ1 : integer;
    variable vQ2 : integer;
    variable vQ3 : integer;
    variable vQ  : integer;
  begin
    vQ1 := to_integer(iQ1);
    vQ2 := to_integer(iQ2);
    vQ3 := to_integer(iQ3);

    if vQ1 > 0 then
      -- Q in 0..323
      vQ := (vQ1 - 1) * 81 + (vQ2 + 4) * 9 + (vQ3 + 4);
    elsif vQ2 > 0 then
      -- Q in 324..359
      vQ := 324 + (vQ2 - 1) * 9 + (vQ3 + 4);
    else
      -- vQ1 = 0 and vQ2 = 0 => Q in 360..364
      -- by A.4.1 if vQ1 = 0 and vQ2 = 0, Q3 belongs to [0, 4]
      vQ := 360 + vQ3;
    end if;

    oQ <= to_unsigned(vQ, oQ'length);
  end process;
end Behavioral;
