use work.Common.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.env.all;

entity tb_A17 is
end;

architecture bench of tb_A17 is
  shared variable err_count : natural := 0;

  procedure check(cond : boolean; msg : string) is
  begin
    if not cond then
      report msg severity error;
      err_count := err_count + 1;
    end if;
  end procedure;

  constant BITNESS : natural := CO_BITNESS_STD;

  signal iRa : unsigned(BITNESS - 1 downto 0) := (others => '0');
  signal iRb : unsigned(BITNESS - 1 downto 0) := (others => '0');
  signal oRI : std_logic;

  procedure check_case(
    constant ra, rb : integer;
    ri_actual       : std_logic
  ) is
    variable exp : std_logic;
  begin
    if ra = rb then
      exp := '1';
    else
      exp := '0';
    end if;

    check(ri_actual = exp,
      "A17 mismatch: Ra=" & integer'image(ra) &
      " Rb=" & integer'image(rb) &
      " exp=" & std_logic'image(exp) &
      " got=" & std_logic'image(ri_actual)
    );
  end procedure;

begin

  dut : entity work.A17_run_interruption_index
    generic map(
      BITNESS => BITNESS
    )
    port map(
      iRa     => iRa,
      iRb     => iRb,
      oRItype => oRI
    );

  stim : process
  begin
    iRa <= to_unsigned(10, iRa'length);
    iRb <= to_unsigned(10, iRb'length);
    wait for 1 ns;
    check_case(10, 10, oRI);

    iRa <= to_unsigned(10, iRa'length);
    iRb <= to_unsigned(11, iRb'length);
    wait for 1 ns;
    check_case(10, 11, oRI);

    iRa <= to_unsigned(10, iRa'length);
    iRb <= to_unsigned(12, iRb'length);
    wait for 1 ns;
    check_case(10, 12, oRI);

    iRa <= to_unsigned(200, iRa'length);
    iRb <= to_unsigned(200, iRb'length);
    wait for 1 ns;
    check_case(200, 200, oRI);

    iRa <= to_unsigned(200, iRa'length);
    iRb <= to_unsigned(197, iRb'length);
    wait for 1 ns;
    check_case(200, 197, oRI);

    iRa <= to_unsigned(0, iRa'length);
    iRb <= to_unsigned(0, iRb'length);
    wait for 1 ns;
    check_case(0, 0, oRI);

    if err_count > 0 then
      report "tb_A17 RESULT: FAIL (" & integer'image(err_count) & " errors)" severity failure;
    else
      report "tb_A17 RESULT: PASS" severity note;
    end if;
    finish;
  end process;

end;
