library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.env.all;

entity tb_A4_2 is
end;

architecture bench of tb_A4_2 is
  shared variable err_count : natural := 0;

  procedure check(cond : boolean; msg : string) is
  begin
    if not cond then
      report msg severity error;
      err_count := err_count + 1;
    end if;
  end procedure;

  signal iQ1 : signed(3 downto 0) := (others => '0');
  signal iQ2 : signed(3 downto 0) := (others => '0');
  signal iQ3 : signed(3 downto 0) := (others => '0');
  signal oQ  : unsigned(8 downto 0);

  type bool_array_t is array (natural range <>) of boolean;

  function expected_map(q1, q2, q3 : integer) return integer is
  begin
    if q1 > 0 then
      return (q1 - 1) * 81 + (q2 + 4) * 9 + (q3 + 4);
    elsif q2 > 0 then
      return 324 + (q2 - 1) * 9 + (q3 + 4);
    else
      return 360 + q3;
    end if;
  end function;

  procedure check_case(
    signal sQ1    : out signed(3 downto 0);
    signal sQ2    : out signed(3 downto 0);
    signal sQ3    : out signed(3 downto 0);
    signal sOut   : in unsigned(8 downto 0);
    q1            : integer;
    q2            : integer;
    q3            : integer;
    variable seen : inout bool_array_t;
    variable cnt  : inout natural
  ) is
    variable exp_q : integer;
    variable got_q : integer;
  begin
    sQ1 <= to_signed(q1, sQ1'length);
    sQ2 <= to_signed(q2, sQ2'length);
    sQ3 <= to_signed(q3, sQ3'length);
    wait for 1 ns;

    exp_q := expected_map(q1, q2, q3);
    got_q := to_integer(sOut);

    check(exp_q >= 0 and exp_q <= 364,
      "A4.2 expected Q out of range for q1=" & integer'image(q1) &
      " q2=" & integer'image(q2) &
      " q3=" & integer'image(q3) &
      " expQ=" & integer'image(exp_q)
    );

    check(got_q = exp_q,
      "A4.2 mapping mismatch: q1=" & integer'image(q1) &
      " q2=" & integer'image(q2) &
      " q3=" & integer'image(q3) &
      " expQ=" & integer'image(exp_q) &
      " gotQ=" & integer'image(got_q)
    );

    check(not seen(exp_q), "A4.2 is not one-to-one: duplicate Q=" & integer'image(exp_q));

    seen(exp_q) := true;
    cnt         := cnt + 1;
  end procedure;
begin
  dut : entity work.A4_2_Q_mapping
    port map(
      iQ1 => iQ1,
      iQ2 => iQ2,
      iQ3 => iQ3,
      oQ  => oQ
    );

  stim : process
    variable seen  : bool_array_t(0 to 364) := (others => false);
    variable count : natural                := 0;
  begin
    for q1 in 0 to 4 loop
      if q1 > 0 then
        for q2 in -4 to 4 loop
          for q3 in -4 to 4 loop
            check_case(iQ1, iQ2, iQ3, oQ, q1, q2, q3, seen, count);
          end loop;
        end loop;
      else
        for q2 in 0 to 4 loop
          if q2 > 0 then
            for q3 in -4 to 4 loop
              check_case(iQ1, iQ2, iQ3, oQ, q1, q2, q3, seen, count);
            end loop;
          else
            for q3 in 0 to 4 loop
              check_case(iQ1, iQ2, iQ3, oQ, q1, q2, q3, seen, count);
            end loop;
          end if;
        end loop;
      end if;
    end loop;

    check(count = 365,
      "A4.2 did not cover all merged contexts. Count=" &
      integer'image(integer(count))
    );

    for q in seen'range loop
      check(seen(q), "A4.2 missing mapped value Q=" & integer'image(q));
    end loop;

    if err_count > 0 then
      report "tb_A4_2 RESULT: FAIL (" & integer'image(err_count) & " errors)" severity failure;
    else
      report "tb_A4_2 RESULT: PASS" severity note;
    end if;
    finish;
  end process;
end;
