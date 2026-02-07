
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.env.all;

entity tb_A3 is
end;

architecture bench of tb_A3 is
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
  constant BITNESS : natural range 8 to 16 := 12;
  -- Ports
  signal iD1          : signed(BITNESS downto 0) := (others => '1');
  signal iD2          : signed(BITNESS downto 0) := (others => '0');
  signal iD3          : signed(BITNESS downto 0) := (others => '0');
  signal oModeRegular : std_logic;
  signal oModeRun     : std_logic;
begin

  A3_mode_selection_inst : entity work.A3_mode_selection
    generic map(
      BITNESS => BITNESS
    )
    port map
    (
      iD1          => iD1,
      iD2          => iD2,
      iD3          => iD3,
      oModeRegular => oModeRegular,
      oModeRun     => oModeRun
    );

  process
  begin

    wait for cStdWait;

    -- All-zero gradients test
    wait for cStdWait;
    iD1 <= to_signed(0, BITNESS + 1);
    iD2 <= to_signed(0, BITNESS + 1);
    iD3 <= to_signed(0, BITNESS + 1);

    wait for cStdWait;
    check(oModeRun = '1', "Test 1 Failed: oModeRun should be asserted for zero gradients");

    check(oModeRegular = '0', "Test 1 Failed: oModeRegular should be deasserted for zero gradients");

    -- Non-zero gradients test
    wait for cStdWait;
    iD1 <= (others => '1');
    iD2 <= (others => '1');
    iD3 <= (others => '1');

    wait for cStdWait;
    check(oModeRun = '0', "Test 2 Failed: oModeRun should be deasserted for non-zero gradients");

    check(oModeRegular = '1', "Test 2 Failed: oModeRegular should be asserted for non-zero gradients");

    if err_count > 0 then
      report "tb_A3 RESULT: FAIL (" & integer'image(err_count) & " errors)" severity failure;
    else
      report "tb_A3 RESULT: PASS" severity note;
    end if;
    finish;
  end process;

end;
