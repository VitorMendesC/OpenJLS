use work.common.all;

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use std.env.all;

entity tb_a4_1 is
end entity tb_a4_1;

architecture bench of tb_a4_1 is

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
  signal oQ1               : signed(3 downto 0);
  signal oQ2               : signed(3 downto 0);
  signal oQ3               : signed(3 downto 0);
  signal oSign             : std_logic;

  function expected_sign (
    q1,
    q2,
    q3 : integer
  ) return std_logic is
  begin

    if (q1 < 0) then
      return CO_SIGN_NEG;
    elsif (q1 = 0 and q2 < 0) then
      return CO_SIGN_NEG;
    elsif (q1 = 0 and q2 = 0 and q3 < 0) then
      return CO_SIGN_NEG;
    else
      return CO_SIGN_POS;
    end if;

  end function expected_sign;

  procedure check_case (
    signal sq1   : out signed(3 downto 0);
    signal sq2   : out signed(3 downto 0);
    signal sq3   : out signed(3 downto 0);
    signal sout1 : in signed(3 downto 0);
    signal sout2 : in signed(3 downto 0);
    signal sout3 : in signed(3 downto 0);
    signal ssign : in std_logic;
    q1           : integer;
    q2           : integer;
    q3           : integer
  ) is

    variable expSign : std_logic;
    variable expQ1   : integer;
    variable expQ2   : integer;
    variable expQ3   : integer;

  begin

    sq1 <= to_signed(q1, sq1'length);
    sq2 <= to_signed(q2, sq2'length);
    sq3 <= to_signed(q3, sq3'length);
    wait for 1 ns;

    expSign := expected_sign(q1, q2, q3);

    if (expSign = CO_SIGN_NEG) then
      expQ1 := -q1;
      expQ2 := -q2;
      expQ3 := -q3;
    else
      expQ1 := q1;
      expQ2 := q2;
      expQ3 := q3;
    end if;

    check(ssign = expSign,
          "A4.1 sign mismatch: Q1=" & integer'image(q1) &
          " Q2=" & integer'image(q2) &
          " Q3=" & integer'image(q3) &
          " expSign=" & std_logic'image(expSign) &
          " gotSign=" & std_logic'image(ssign)
        );

    check(sout1 = to_signed(expQ1, sout1'length),
          "A4.1 Q1 mismatch: Q1=" & integer'image(q1) &
          " Q2=" & integer'image(q2) &
          " Q3=" & integer'image(q3) &
          " exp=" & integer'image(expQ1) &
          " got=" & integer'image(to_integer(sout1))
        );

    check(sout2 = to_signed(expQ2, sout2'length),
          "A4.1 Q2 mismatch: Q1=" & integer'image(q1) &
          " Q2=" & integer'image(q2) &
          " Q3=" & integer'image(q3) &
          " exp=" & integer'image(expQ2) &
          " got=" & integer'image(to_integer(sout2))
        );

    check(sout3 = to_signed(expQ3, sout3'length),
          "A4.1 Q3 mismatch: Q1=" & integer'image(q1) &
          " Q2=" & integer'image(q2) &
          " Q3=" & integer'image(q3) &
          " exp=" & integer'image(expQ3) &
          " got=" & integer'image(to_integer(sout3))
        );

  end procedure check_case;

begin

  dut : entity work.a4_1_quant_gradient_merging(behavioral)

    port map (
      iQ1   => iQ1,
      iQ2   => iQ2,
      iQ3   => iQ3,
      oQ1   => oQ1,
      oQ2   => oQ2,
      oQ3   => oQ3,
      oSign => oSign
    );

  stim : process is
  begin

    -- Initial values (no defaults — set explicitly here)
    iQ1 <= (others => '0');
    iQ2 <= (others => '0');
    iQ3 <= (others => '0');

    for q1 in -4 to 4 loop

      for q2 in -4 to 4 loop

        for q3 in -4 to 4 loop

          check_case(iQ1, iQ2, iQ3, oQ1, oQ2, oQ3, oSign, q1, q2, q3);

        end loop;

      end loop;

    end loop;

    if (errCount > 0) then
      report "tb_A4_1 RESULT: FAIL (" & integer'image(errCount) & " errors)"
        severity failure;
    else
      report "tb_A4_1 RESULT: PASS"
        severity note;
    end if;

    finish;

  end process stim;

end architecture bench;
