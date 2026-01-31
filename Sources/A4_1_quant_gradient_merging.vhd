----------------------------------------------------------------------------------
-- Company:
-- Engineer:    Vitor Mendes Camilo
-- 
-- Create Date: 08/23/2025 06:20:54 PM
-- Design Name: 
-- Module Name: quant_gradient_merging - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:               Code segment A.4.1 
--                                    Text only, described on section A.3.4
-- 
----------------------------------------------------------------------------------
use work.Common.all;

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity A4_1_quant_gradient_merging is
  port (
    iQ1   : in signed(3 downto 0);
    iQ2   : in signed(3 downto 0);
    iQ3   : in signed(3 downto 0);
    oQ1   : out signed(3 downto 0);
    oQ2   : out signed(3 downto 0);
    oQ3   : out signed(3 downto 0);
    oSign : out std_logic
  );
end A4_1_quant_gradient_merging;

architecture Behavioral of A4_1_quant_gradient_merging is
  signal sSign : std_logic;

begin

  -- Sign of first non-zero (1 if negative)
  sSign <= CO_SIGN_NEG when iQ1 < 0 else
    CO_SIGN_NEG when (iQ1 = 0 and iQ2 < 0) else
    CO_SIGN_NEG when (iQ1 = 0 and iQ2 = 0 and iQ3 < 0) else
    CO_SIGN_POS;

  -- Flip quantized values if sign is negative
  oQ1 <= - iQ1 when sSign = CO_SIGN_NEG else
    iQ1;
  oQ2 <= - iQ2 when sSign = CO_SIGN_NEG else
    iQ2;
  oQ3 <= - iQ3 when sSign = CO_SIGN_NEG else
    iQ3;

  oSign <= sSign;

end Behavioral;
