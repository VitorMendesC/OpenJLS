
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.env.all;

entity tb_A5 is
end;

architecture bench of tb_A5 is
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
  -- Generics
  constant BITNESS : natural range 8 to 16 := 12;
  constant MAX_VAL : natural               := 2 ** BITNESS - 1;
  -- Ports
  signal iA  : unsigned (BITNESS - 1 downto 0);
  signal iB  : unsigned (BITNESS - 1 downto 0);
  signal iC  : unsigned (BITNESS - 1 downto 0);
  signal oPx : unsigned (BITNESS - 1 downto 0);

  function predict(a, b, c : natural) return natural is
    variable max_ab          : natural;
    variable min_ab          : natural;
  begin
    if a >= b then
      max_ab := a;
      min_ab := b;
    else
      max_ab := b;
      min_ab := a;
    end if;

    if c >= max_ab then
      return min_ab;
    elsif c <= min_ab then
      return max_ab;
    else
      return a + b - c;
    end if;
  end function;

  function lfsr_next(s : unsigned(31 downto 0)) return unsigned is
    variable v           : unsigned(31 downto 0) := s;
    variable bit         : std_logic;
  begin
    bit := v(31) xor v(21) xor v(1) xor v(0);
    v   := v(30 downto 0) & bit;
    return v;
  end function;

  procedure check_case(
    signal sA  : out unsigned;
    signal sB  : out unsigned;
    signal sC  : out unsigned;
    signal sPx : in unsigned;
    a, b, c    : natural
  ) is
    variable exp_px : natural;
  begin
    sA <= to_unsigned(a, sA'length);
    sB <= to_unsigned(b, sB'length);
    sC <= to_unsigned(c, sC'length);
    wait for 1 ns;
    exp_px := predict(a, b, c);
    check(sPx = to_unsigned(exp_px, sPx'length),
      "Mismatch: A=" & integer'image(a) &
      " B=" & integer'image(b) &
      " C=" & integer'image(c) &
      " exp=" & integer'image(exp_px) &
      " got=" & integer'image(to_integer(sPx))
    );
  end procedure;
begin

  A5_edge_detecting_predictor_inst : entity work.A5_edge_detecting_predictor
    generic map(
      BITNESS => BITNESS
    )
    port map
    (
      iA  => iA,
      iB  => iB,
      iC  => iC,
      oPx => oPx
    );
  -- clk <= not clk after clk_period/2;

  stim : process
    variable lfsr    : unsigned(31 downto 0) := x"1A2B3C4D";
    variable a, b, c : natural;
  begin
    -- Directed edge cases
    check_case(iA, iB, iC, oPx, 10, 5, 10); -- c == max
    check_case(iA, iB, iC, oPx, 10, 5, 15); -- c > max
    check_case(iA, iB, iC, oPx, 10, 5, 5); -- c == min
    check_case(iA, iB, iC, oPx, 10, 5, 2); -- c < min
    check_case(iA, iB, iC, oPx, 10, 5, 7); -- mid case
    check_case(iA, iB, iC, oPx, 9, 9, 9); -- equal a,b,c
    check_case(iA, iB, iC, oPx, 9, 9, 0); -- equal a,b, c < min
    check_case(iA, iB, iC, oPx, 0, 0, 0);
    check_case(iA, iB, iC, oPx, 0, MAX_VAL, MAX_VAL);
    check_case(iA, iB, iC, oPx, MAX_VAL, 0, MAX_VAL);
    check_case(iA, iB, iC, oPx, MAX_VAL, MAX_VAL, MAX_VAL);
    check_case(iA, iB, iC, oPx, MAX_VAL, 0, 0);

    -- Pseudo-random coverage
    for i in 0 to 999 loop
      lfsr := lfsr_next(lfsr);
      a    := to_integer(lfsr(BITNESS - 1 downto 0));
      lfsr := lfsr_next(lfsr);
      b    := to_integer(lfsr(BITNESS - 1 downto 0));
      lfsr := lfsr_next(lfsr);
      c    := to_integer(lfsr(BITNESS - 1 downto 0));
      check_case(iA, iB, iC, oPx, a, b, c);
    end loop;

    if err_count > 0 then
      report "tb_A5 RESULT: FAIL (" & integer'image(err_count) & " errors)" severity failure;
    else
      report "tb_A5 RESULT: PASS" severity note;
    end if;
    finish;
  end process;
end;
