
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.env.all;

entity tb_A2 is
end;

architecture bench of tb_A2 is
  shared variable err_count : natural := 0;

  procedure check(cond : boolean; msg : string) is
  begin
    if not cond then
      report msg severity error;
      err_count := err_count + 1;
    end if;
  end procedure;

  constant BITNESS : natural range 8 to 16 := 12;
  constant NEAR0   : natural := 0;
  constant NEAR2   : natural := 2;

  signal iD1 : signed(BITNESS downto 0) := (others => '0');
  signal iD2 : signed(BITNESS downto 0) := (others => '0');
  signal iD3 : signed(BITNESS downto 0) := (others => '0');

  signal oRunN0 : std_logic;
  signal oRegN0 : std_logic;
  signal oRunN2 : std_logic;
  signal oRegN2 : std_logic;

  function is_run(d1, d2, d3 : integer; near_v : natural) return std_logic is
  begin
    if (abs(d1) <= integer(near_v)) and (abs(d2) <= integer(near_v)) and (abs(d3) <= integer(near_v)) then
      return '1';
    else
      return '0';
    end if;
  end function;

  procedure check_case(
    d1, d2, d3 : integer;
    run0, reg0 : std_logic;
    run2, reg2 : std_logic
  ) is
    variable exp0 : std_logic;
    variable exp2 : std_logic;
  begin
    exp0 := is_run(d1, d2, d3, NEAR0);
    exp2 := is_run(d1, d2, d3, NEAR2);

    check(run0 = exp0,
      "A2 NEAR=0 mismatch: D1=" & integer'image(d1) &
      " D2=" & integer'image(d2) &
      " D3=" & integer'image(d3) &
      " expRun=" & std_logic'image(exp0) &
      " gotRun=" & std_logic'image(run0)
    );

    check(run2 = exp2,
      "A2 NEAR=2 mismatch: D1=" & integer'image(d1) &
      " D2=" & integer'image(d2) &
      " D3=" & integer'image(d3) &
      " expRun=" & std_logic'image(exp2) &
      " gotRun=" & std_logic'image(run2)
    );

    check(reg0 = not exp0, "A2 NEAR=0 regular mismatch");
    check(reg2 = not exp2, "A2 NEAR=2 regular mismatch");
  end procedure;

begin

  dut_n0 : entity work.A2_mode_selection
    generic map(
      BITNESS => BITNESS,
      NEAR    => NEAR0
    )
    port map(
      iD1          => iD1,
      iD2          => iD2,
      iD3          => iD3,
      oModeRegular => oRegN0,
      oModeRun     => oRunN0
    );

  dut_n2 : entity work.A2_mode_selection
    generic map(
      BITNESS => BITNESS,
      NEAR    => NEAR2
    )
    port map(
      iD1          => iD1,
      iD2          => iD2,
      iD3          => iD3,
      oModeRegular => oRegN2,
      oModeRun     => oRunN2
    );

  stim : process
  begin
    iD1 <= to_signed(0, iD1'length);
    iD2 <= to_signed(0, iD2'length);
    iD3 <= to_signed(0, iD3'length);
    wait for 1 ns;
    check_case(0, 0, 0, oRunN0, oRegN0, oRunN2, oRegN2);

    iD1 <= to_signed(1, iD1'length);
    iD2 <= to_signed(0, iD2'length);
    iD3 <= to_signed(0, iD3'length);
    wait for 1 ns;
    check_case(1, 0, 0, oRunN0, oRegN0, oRunN2, oRegN2);

    iD1 <= to_signed(2, iD1'length);
    iD2 <= to_signed(-2, iD2'length);
    iD3 <= to_signed(2, iD3'length);
    wait for 1 ns;
    check_case(2, -2, 2, oRunN0, oRegN0, oRunN2, oRegN2);

    iD1 <= to_signed(3, iD1'length);
    iD2 <= to_signed(0, iD2'length);
    iD3 <= to_signed(0, iD3'length);
    wait for 1 ns;
    check_case(3, 0, 0, oRunN0, oRegN0, oRunN2, oRegN2);

    iD1 <= to_signed(-3, iD1'length);
    iD2 <= to_signed(2, iD2'length);
    iD3 <= to_signed(-1, iD3'length);
    wait for 1 ns;
    check_case(-3, 2, -1, oRunN0, oRegN0, oRunN2, oRegN2);

    iD1 <= to_signed(2, iD1'length);
    iD2 <= to_signed(3, iD2'length);
    iD3 <= to_signed(1, iD3'length);
    wait for 1 ns;
    check_case(2, 3, 1, oRunN0, oRegN0, oRunN2, oRegN2);

    iD1 <= to_signed(100, iD1'length);
    iD2 <= to_signed(0, iD2'length);
    iD3 <= to_signed(0, iD3'length);
    wait for 1 ns;
    check_case(100, 0, 0, oRunN0, oRegN0, oRunN2, oRegN2);

    if err_count > 0 then
      report "tb_A2 RESULT: FAIL (" & integer'image(err_count) & " errors)" severity failure;
    else
      report "tb_A2 RESULT: PASS" severity note;
    end if;
    finish;
  end process;

end;
