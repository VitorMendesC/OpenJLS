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

use work.Common.all;

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity A10_compute_k is
  generic (
    A_WIDTH : natural := CO_AQ_WIDTH_STD;
    K_WIDTH : natural := CO_K_WIDTH_STD;
    N_WIDTH : natural := CO_NQ_WIDTH_STD
  );
  port (
    iNq : in unsigned (N_WIDTH - 1 downto 0);
    iAq : in unsigned (A_WIDTH - 1 downto 0);
    oK  : out unsigned (K_WIDTH - 1 downto 0)
  );
end A10_compute_k;

architecture Behavioral of A10_compute_k is
  -- Worst case: Nq = 1 and Aq = 2^A_WIDTH - 1
  constant MAX_K : natural := A_WIDTH;
  constant W     : natural := A_WIDTH + 1;
begin

  -- Parallel formulation: compute all candidate shifts up-front, compare each
  -- against Aq, then priority-encode for the smallest index whose shift
  -- reaches/exceeds Aq. Depth collapses from MAX_K ripple levels to one
  -- compare + log2(MAX_K+1) encoder levels.
  process (iNq, iAq)
    variable vAq    : unsigned(W - 1 downto 0);
    variable vNq    : unsigned(W - 1 downto 0);
    variable vMatch : std_logic_vector(MAX_K downto 0);
    variable vK     : unsigned(oK'range);
  begin
    vAq := resize(iAq, W);
    vNq := resize(iNq, W);

    -- Parallel compares: vMatch(k) = '1' iff (Nq << k) >= Aq
    for k in 0 to MAX_K loop
      if shift_left(vNq, k) >= vAq then
        vMatch(k) := '1';
      else
        vMatch(k) := '0';
      end if;
    end loop;

    -- Priority encode: smallest index with match='1' wins.
    -- Loop high→low, last assignment carried forward yields the lowest match.
    vK := to_unsigned(MAX_K + 1, vK'length);
    for k in MAX_K downto 0 loop
      if vMatch(k) = '1' then
        vK := to_unsigned(k, vK'length);
      end if;
    end loop;

    oK <= vK;
  end process;
end Behavioral;
