use work.Common.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.env.all;

entity tb_A4_1 is
end;

architecture bench of tb_A4_1 is
  shared variable err_count : natural := 0;

  procedure check(cond : boolean; msg : string) is
  begin
    if not cond then
      report msg severity error;
      err_count := err_count + 1;
    end if;
  end procedure;

  signal iQ1   : signed(3 downto 0) := (others => '0');
  signal iQ2   : signed(3 downto 0) := (others => '0');
  signal iQ3   : signed(3 downto 0) := (others => '0');
  signal oQ1   : signed(3 downto 0);
  signal oQ2   : signed(3 downto 0);
  signal oQ3   : signed(3 downto 0);
  signal oSign : std_logic;

  function expected_sign(q1, q2, q3 : integer) return std_logic is
  begin
    if q1 < 0 then
      return CO_SIGN_NEG;
    elsif q1 = 0 and q2 < 0 then
      return CO_SIGN_NEG;
    elsif q1 = 0 and q2 = 0 and q3 < 0 then
      return CO_SIGN_NEG;
    else
      return CO_SIGN_POS;
    end if;
  end function;

  procedure check_case(
    signal sQ1   : out signed(3 downto 0);
    signal sQ2   : out signed(3 downto 0);
    signal sQ3   : out signed(3 downto 0);
    signal sOut1 : in signed(3 downto 0);
    signal sOut2 : in signed(3 downto 0);
    signal sOut3 : in signed(3 downto 0);
    signal sSign : in std_logic;
    q1           : integer;
    q2           : integer;
    q3           : integer
  ) is
    variable exp_sign : std_logic;
    variable exp_q1   : integer;
    variable exp_q2   : integer;
    variable exp_q3   : integer;
  begin
    sQ1 <= to_signed(q1, sQ1'length);
    sQ2 <= to_signed(q2, sQ2'length);
    sQ3 <= to_signed(q3, sQ3'length);
    wait for 1 ns;

    exp_sign := expected_sign(q1, q2, q3);
    if exp_sign = CO_SIGN_NEG then
      exp_q1 := -q1;
      exp_q2 := -q2;
      exp_q3 := -q3;
    else
      exp_q1 := q1;
      exp_q2 := q2;
      exp_q3 := q3;
    end if;

    check(sSign = exp_sign,
      "A4.1 sign mismatch: Q1=" & integer'image(q1) &
      " Q2=" & integer'image(q2) &
      " Q3=" & integer'image(q3) &
      " expSign=" & std_logic'image(exp_sign) &
      " gotSign=" & std_logic'image(sSign)
    );

    check(sOut1 = to_signed(exp_q1, sOut1'length),
      "A4.1 Q1 mismatch: Q1=" & integer'image(q1) &
      " Q2=" & integer'image(q2) &
      " Q3=" & integer'image(q3) &
      " exp=" & integer'image(exp_q1) &
      " got=" & integer'image(to_integer(sOut1))
    );

    check(sOut2 = to_signed(exp_q2, sOut2'length),
      "A4.1 Q2 mismatch: Q1=" & integer'image(q1) &
      " Q2=" & integer'image(q2) &
      " Q3=" & integer'image(q3) &
      " exp=" & integer'image(exp_q2) &
      " got=" & integer'image(to_integer(sOut2))
    );

    check(sOut3 = to_signed(exp_q3, sOut3'length),
      "A4.1 Q3 mismatch: Q1=" & integer'image(q1) &
      " Q2=" & integer'image(q2) &
      " Q3=" & integer'image(q3) &
      " exp=" & integer'image(exp_q3) &
      " got=" & integer'image(to_integer(sOut3))
    );
  end procedure;
begin
  dut : entity work.A4_1_quant_gradient_merging
    port map(
      iQ1   => iQ1,
      iQ2   => iQ2,
      iQ3   => iQ3,
      oQ1   => oQ1,
      oQ2   => oQ2,
      oQ3   => oQ3,
      oSign => oSign
    );

  stim : process
  begin
    for q1 in -4 to 4 loop
      for q2 in -4 to 4 loop
        for q3 in -4 to 4 loop
          check_case(iQ1, iQ2, iQ3, oQ1, oQ2, oQ3, oSign, q1, q2, q3);
        end loop;
      end loop;
    end loop;

    if err_count > 0 then
      report "tb_A4_1 RESULT: FAIL (" & integer'image(err_count) & " errors)" severity failure;
    else
      report "tb_A4_1 RESULT: PASS" severity note;
    end if;
    finish;
  end process;
end;
