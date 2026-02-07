----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 01/17/2026 01:39:27 AM
-- Design Name: 
-- Module Name: tb_A1 - Behavioral
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

use std.env.all;

entity tb_A1 is
end;

architecture bench of tb_A1 is
  shared variable err_count : natural := 0;

  procedure check(cond : boolean; msg : string) is
  begin
    if not cond then
      report msg severity error;
      err_count := err_count + 1;
    end if;
  end procedure;

  -- Clock period
  constant cStdWait : time := 100 ns;
  -- Generics
  constant BITNESS   : natural range 8 to 16 := 12;
  constant MAX_VALUE : natural               := 2 ** BITNESS - 1;

  -- Ports
  signal iA  : unsigned (BITNESS - 1 downto 0) := (others => '0');
  signal iB  : unsigned (BITNESS - 1 downto 0) := (others => '0');
  signal iC  : unsigned (BITNESS - 1 downto 0) := (others => '0');
  signal iD  : unsigned (BITNESS - 1 downto 0) := (others => '0');
  signal oD1 : signed (BITNESS downto 0)       := (others => '0');
  signal oD2 : signed (BITNESS downto 0)       := (others => '0');
  signal oD3 : signed (BITNESS downto 0)       := (others => '0');
begin

  A1_gradient_comp_inst : entity work.A1_gradient_comp
    generic map(
      BITNESS => BITNESS
    )
    port map
    (
      iA  => iA,
      iB  => iB,
      iC  => iC,
      iD  => iD,
      oD1 => oD1,
      oD2 => oD2,
      oD3 => oD3
    );

  process
  begin

    -- Simple test case
    wait for cStdWait;
    iD <= to_unsigned(7, BITNESS);
    iB <= to_unsigned(6, BITNESS);
    iC <= to_unsigned(4, BITNESS);
    iA <= to_unsigned(1, BITNESS);

    wait for cStdWait;
    check(oD1 = to_signed(1, BITNESS + 1), "Test 1 Failed: oD1 incorrect");

    check(oD2 = to_signed(2, BITNESS + 1), "Test 1 Failed: oD2 incorrect");

    check(oD3 = to_signed(3, BITNESS + 1), "Test 1 Failed: oD3 incorrect");

    -- Simple negative test case
    wait for cStdWait;
    iD <= to_unsigned(9, BITNESS);
    iB <= to_unsigned(10, BITNESS);
    iC <= to_unsigned(12, BITNESS);
    iA <= to_unsigned(15, BITNESS);

    wait for cStdWait;
    check(oD1 = to_signed(-1, BITNESS + 1), "Test 2 Failed: oD1 incorrect");

    check(oD2 = to_signed(-2, BITNESS + 1), "Test 2 Failed: oD2 incorrect");

    check(oD3 = to_signed(-3, BITNESS + 1), "Test 2 Failed: oD3 incorrect");

    -- Close to MAX_VALUE test case
    wait for cStdWait;
    iD <= to_unsigned(9, BITNESS);
    iB <= to_unsigned(MAX_VALUE - 1, BITNESS);
    iC <= to_unsigned(1, BITNESS);
    iA <= to_unsigned(MAX_VALUE, BITNESS);

    wait for cStdWait;
    check(oD1 = to_signed(9 - MAX_VALUE + 1, BITNESS + 1), "Test 3 Failed: oD1 incorrect");

    check(oD2 = to_signed(MAX_VALUE - 1 - 1, BITNESS + 1), "Test 3 Failed: oD2 incorrect");

    check(oD3 = to_signed(1 - MAX_VALUE, BITNESS + 1), "Test 3 Failed: oD3 incorrect");

    if err_count > 0 then
      report "tb_A1 RESULT: FAIL (" & integer'image(err_count) & " errors)" severity failure;
    else
      report "tb_A1 RESULT: PASS" severity note;
    end if;
    finish;

  end process;

end;