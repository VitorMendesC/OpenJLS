----------------------------------------------------------------------------------
-- Company:
-- Engineer:    Vitor Mendes Camilo
-- 
-- Create Date: 08/29/2025 11:04:42 PM
-- Design Name: 
-- Module Name: A10_compute_k - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:             Code segment A.10             
--                                  Computation of the Golomg coding variable k 
--
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use work.Common.all;

entity A10_compute_k is
  generic (
    N_WIDTH : natural := 12;
    A_WIDTH : natural := 12;
    K_WIDTH : natural := 4
  );
  port (
    iNq : in unsigned (N_WIDTH - 1 downto 0);
    iAq : in unsigned (A_WIDTH - 1 downto 0);
    oK  : out unsigned (K_WIDTH - 1 downto 0)
  );
end A10_compute_k;

architecture Behavioral of A10_compute_k is
begin

  process (iNq, iAq)
    variable vK     : unsigned (K_WIDTH - 1 downto 0);
    variable vNqTmp : unsigned(N_WIDTH - 1 downto 0);

  begin

    vK     := (others => '0');
    vNqTmp := iNq;

    for i in 0 to vNqTmp'high loop
      if (vNqTmp < iAq) then
        vNqTmp := SHIFT_LEFT(vNqTmp, 1);
        vK     := vK + 1;
      else
        exit;
      end if;
    end loop;

    oK <= vK;
  end process;
end Behavioral;
