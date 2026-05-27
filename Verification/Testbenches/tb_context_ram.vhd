----------------------------------------------------------------------------------
-- Company:
-- Engineer:    Vitor Mendes Camilo
-- 
-- Create Date: 09/04/2025 09:12:23 AM
-- Design Name: 
-- Module Name: tb_context_ram - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library openlogic_base;
use openlogic_base.olo_base_pkg_math.all;

use std.env.all;

entity tb_context_ram is
end;

architecture bench of tb_context_ram is
  shared variable err_count : natural := 0;

  procedure check(cond : boolean; msg : string) is
  begin
    if not cond then
      report msg severity error;
      err_count := err_count + 1;
    end if;
  end procedure;

  -- Clock period
  constant clk_period : time := 5 ns;
  constant cStdWait   : time := 10 * clk_period;

  -- Generics
  constant RAM_DEPTH  : positive := 1024;
  constant WORD_WIDTH : positive := 32;
  -- Ports
  signal iClk    : std_logic                                          := '1';
  signal iWrAddr : std_logic_vector(log2ceil(RAM_DEPTH) - 1 downto 0) := (others => '0');
  signal iWrEn   : std_logic                                          := '0';
  signal iWrData : std_logic_vector(WORD_WIDTH - 1 downto 0)          := (others => '0');
  signal iRdAddr : std_logic_vector(log2ceil(RAM_DEPTH) - 1 downto 0) := (others => '0');
  signal iRdEn   : std_logic                                          := '0';
  signal oRdData : std_logic_vector(WORD_WIDTH - 1 downto 0);
begin

  context_ram_inst : entity work.context_ram
    port map
    (
      iClk    => iClk,
      iWrAddr => iWrAddr,
      iWrEn   => iWrEn,
      iWrData => iWrData,
      iRdAddr => iRdAddr,
      iRdEn   => iRdEn,
      oRdData => oRdData
    );

  iClk <= not iClk after clk_period/2;

  process
  begin

    -- Feed-forward test
    wait for cStdWait;
    iWrEn   <= '1';
    iRdEn   <= '1';
    iWrData <= x"BEEBEBEE";

    wait for clk_period;
    check(oRdData = x"BEEBEBEE", "Feed-forward test failed!");

    iWrEn <= '0';
    iRdEn <= '0';

    wait for cStdWait;

    if err_count > 0 then
      report "tb_context_ram RESULT: FAIL (" & integer'image(err_count) & " errors)" severity failure;
    else
      report "tb_context_ram RESULT: PASS" severity note;
    end if;
    finish;

  end process;

end;
