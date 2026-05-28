library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use std.env.all;

entity tb_a4_2 is
end entity tb_a4_2;

architecture bench of tb_a4_2 is

  shared variable errCount : natural;

  procedure check (
    cond : boolean;
    msg  : string
  ) is
  begin

    if (not cond) then
      report msg
        severity error;
      errCount := errCount + 1;
    end if;

  end procedure check;

  signal iQ1               : signed(3 downto 0);
  signal iQ2               : signed(3 downto 0);
  signal iQ3               : signed(3 downto 0);
  signal oQ                : unsigned(8 downto 0);

  type bool_array_t is array (natural range <>) of boolean;

  function expected_map (
    q1,
    q2,
    q3 : integer
  ) return integer is
  begin

    return 81 * q1 + 9 * q2 + q3;

  end function expected_map;

  procedure check_case (
    signal sq1    : out signed(3 downto 0);
    signal sq2    : out signed(3 downto 0);
    signal sq3    : out signed(3 downto 0);
    signal sout   : in unsigned(8 downto 0);
    q1            : integer;
    q2            : integer;
    q3            : integer;
    variable seen : inout bool_array_t;
    variable cnt  : inout natural
  ) is

    variable expQ : integer;
    variable gotQ : integer;

  begin

    sq1 <= to_signed(q1, sq1'length);
    sq2 <= to_signed(q2, sq2'length);
    sq3 <= to_signed(q3, sq3'length);
    wait for 1 ns;

    expQ := expected_map(q1, q2, q3);
    gotQ := to_integer(sout);

    check(expQ >= 0 and expQ <= 364,
          "A4.2 expected Q out of range for q1=" & integer'image(q1) &
          " q2=" & integer'image(q2) &
          " q3=" & integer'image(q3) &
          " expQ=" & integer'image(expQ)
        );

    check(gotQ = expQ,
          "A4.2 mapping mismatch: q1=" & integer'image(q1) &
          " q2=" & integer'image(q2) &
          " q3=" & integer'image(q3) &
          " expQ=" & integer'image(expQ) &
          " gotQ=" & integer'image(gotQ)
        );

    check(not seen(expQ), "A4.2 is not one-to-one: duplicate Q=" & integer'image(expQ));

    seen(expQ) := true;
    cnt        := cnt + 1;

  end procedure check_case;

begin

  dut : entity work.a4_2_q_mapping(behavioral)

    port map (
      iQ1 => iQ1,
      iQ2 => iQ2,
      iQ3 => iQ3,
      oQ  => oQ
    );

  stim : process is

    variable seen  : bool_array_t(0 to 364);
    variable count : natural;

  begin

    -- Initial values (no defaults — set explicitly here)
    iQ1 <= (others => '0');
    iQ2 <= (others => '0');
    iQ3 <= (others => '0');

    for q1 in 0 to 4 loop

      if (q1 > 0) then

        for q2 in -4 to 4 loop

          for q3 in -4 to 4 loop

            check_case(iQ1, iQ2, iQ3, oQ, q1, q2, q3, seen, count);

          end loop;

        end loop;

      else

        for q2 in 0 to 4 loop

          if (q2 > 0) then

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

    if (errCount > 0) then
      report "tb_A4_2 RESULT: FAIL (" & integer'image(errCount) & " errors)"
        severity failure;
    else
      report "tb_A4_2 RESULT: PASS"
        severity note;
    end if;

    finish;

  end process stim;

end architecture bench;
