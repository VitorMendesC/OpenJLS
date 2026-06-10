library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library osvvm;
  context osvvm.OsvvmContext;

package tb_support_pkg is

  constant CLK_PERIOD_DEFAULT : time := 10 ns;

  procedure clk_tick (
    signal   clk    : in    std_logic;
    constant cycles : in    natural := 1
  );

  procedure apply_reset (
    signal   clk    : in    std_logic;
    signal   rst    : out   std_logic;
    constant cycles : in    natural := 4;
    constant active : in    std_logic := '1'
  );

  procedure end_of_test (
    constant test_name : in string
  );

end package tb_support_pkg;

package body tb_support_pkg is

  procedure clk_tick (
    signal   clk    : in    std_logic;
    constant cycles : in    natural := 1
  ) is
  begin
    for i in 1 to cycles loop
      wait until rising_edge(clk);
    end loop;
  end procedure;

  procedure apply_reset (
    signal   clk    : in    std_logic;
    signal   rst    : out   std_logic;
    constant cycles : in    natural := 4;
    constant active : in    std_logic := '1'
  ) is
  begin
    rst <= active;
    for i in 1 to cycles loop
      wait until rising_edge(clk);
    end loop;
    rst <= not active;
    wait until rising_edge(clk);
  end procedure;

  procedure end_of_test (
    constant test_name : in string
  ) is
    variable errors : integer;
  begin
    -- EndOfTestReports = ReportAlerts + YAML emission (alerts, functional
    -- coverage, scoreboards) consumed by the OSVVM script flow's HTML reports.
    errors := EndOfTestReports;
    if errors = 0 then
      report test_name & ": PASS" severity note;
    else
      report test_name & ": FAIL" severity failure;
    end if;
    std.env.stop;
  end procedure;

end package body tb_support_pkg;
