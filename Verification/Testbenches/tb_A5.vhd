
library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use std.env.all;

entity tb_a5 is
end entity tb_a5;

architecture bench of tb_a5 is

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

  -- Clock period
  constant CLK_PERIOD      : time := 5 ns;
  -- Generics
  constant BITNESS         : natural range 8 to 16 := 12;
  constant MAX_VAL         : natural               := 2 ** BITNESS - 1;
  -- Ports
  signal iA                : unsigned (BITNESS - 1 downto 0);
  signal iB                : unsigned (BITNESS - 1 downto 0);
  signal iC                : unsigned (BITNESS - 1 downto 0);
  signal oPx               : unsigned (BITNESS - 1 downto 0);

  function predict (
    a,
    b,
    c : natural
  ) return natural is

    variable maxAb : natural;
    variable minAb : natural;

  begin

    if (a >= b) then
      maxAb := a;
      minAb := b;
    else
      maxAb := b;
      minAb := a;
    end if;

    if (c >= maxAb) then
      return minAb;
    elsif (c <= minAb) then
      return maxAb;
    else
      return a + b - c;
    end if;

  end function predict;

  function lfsr_next (
    s : unsigned(31 downto 0)
  ) return unsigned is

    variable v   : unsigned(31 downto 0);
    variable bit : std_logic;

  begin

    bit := v(31) xor v(21) xor v(1) xor v(0);
    v   := v(30 downto 0) & bit;
    return v;

  end function lfsr_next;

  procedure check_case (
    signal sa  : out unsigned;
    signal sb  : out unsigned;
    signal sc  : out unsigned;
    signal spx : in unsigned;
    a,
    b,
    c          : natural
  ) is

    variable expPx : natural;

  begin

    sa    <= to_unsigned(a, sa'length);
    sb    <= to_unsigned(b, sb'length);
    sc    <= to_unsigned(c, sc'length);
    wait for 1 ns;
    expPx := predict(a, b, c);
    check(spx = to_unsigned(expPx, spx'length),
          "Mismatch: A=" & integer'image(a) &
          " B=" & integer'image(b) &
          " C=" & integer'image(c) &
          " exp=" & integer'image(expPx) &
          " got=" & integer'image(to_integer(spx))
        );

  end procedure check_case;

begin

  a5_edge_detecting_predictor_inst : entity work.a5_edge_detecting_predictor(behavioral)

    generic map (
      BITNESS => BITNESS
    )
    port map (
      iA      => iA,
      iB      => iB,
      iC      => iC,
      oPx     => oPx
    );

  -- clk <= not clk after clk_period/2;

  stim : process is

    variable lfsr : unsigned(31 downto 0);
    variable a    : natural;
    variable b    : natural;
    variable c    : natural;

  begin

    -- Directed edge cases
    check_case(iA, iB, iC, oPx, 10, 5, 10);                                 -- c == max
    check_case(iA, iB, iC, oPx, 10, 5, 15);                                 -- c > max
    check_case(iA, iB, iC, oPx, 10, 5, 5);                                  -- c == min
    check_case(iA, iB, iC, oPx, 10, 5, 2);                                  -- c < min
    check_case(iA, iB, iC, oPx, 10, 5, 7);                                  -- mid case
    check_case(iA, iB, iC, oPx, 9, 9, 9);                                   -- equal a,b,c
    check_case(iA, iB, iC, oPx, 9, 9, 0);                                   -- equal a,b, c < min
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

    if (errCount > 0) then
      report "tb_A5 RESULT: FAIL (" & integer'image(errCount) & " errors)"
        severity failure;
    else
      report "tb_A5 RESULT: PASS"
        severity note;
    end if;

    finish;

  end process stim;

end architecture bench;
