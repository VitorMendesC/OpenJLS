library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use std.env.all;

entity tb_a9 is
end entity tb_a9;

architecture bench of tb_a9 is

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

  -- Generics
  constant BITNESS         : natural range 8 to 16 := 12;
  constant MAX_VAL         : natural               := 2 ** BITNESS - 1;
  constant C_RANGE         : natural               := MAX_VAL + 1;
  constant HALF_RANGE      : natural               := (C_RANGE + 1) / 2;

  -- Ports
  signal iErrorVal         : signed (BITNESS downto 0);
  signal oErrorVal         : signed (BITNESS downto 0);

  function modulo_reduce (
    errval : integer
  ) return integer is

    variable v : integer;

  begin

    if (v < 0) then
      v := v + integer(C_RANGE);
    end if;

    if (v >= integer(HALF_RANGE)) then
      v := v - integer(C_RANGE);
    end if;

    return v;

  end function modulo_reduce;

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
    signal sin  : out signed;
    signal sout : in signed;
    errval      : integer
  ) is

    variable expV : integer;

  begin

    sin  <= to_signed(errval, sin'length);
    wait for 1 ns;
    expV := modulo_reduce(errval);
    check(sout = to_signed(expV, sout'length),
          "A9 mismatch: Errval=" & integer'image(errval) &
          " Exp=" & integer'image(expV) &
          " Got=" & integer'image(to_integer(sout))
        );

  end procedure check_case;

begin

  a9_modulo_reduction_inst : entity work.a9_modulo_reduction(behavioral)

    generic map (
      BITNESS   => BITNESS
    )
    port map (
      iErrorVal => iErrorVal,
      oErrorVal => oErrorVal
    );

  stim : process is

    variable lfsr : unsigned(31 downto 0);
    variable errv : integer;

  begin

    -- Directed boundary cases
    check_case(iErrorVal, oErrorVal, 0);
    check_case(iErrorVal, oErrorVal, 1);
    check_case(iErrorVal, oErrorVal, -1);
    check_case(iErrorVal, oErrorVal, integer(HALF_RANGE) - 1);
    check_case(iErrorVal, oErrorVal, integer(HALF_RANGE));
    check_case(iErrorVal, oErrorVal, integer(HALF_RANGE) + 1);
    check_case(iErrorVal, oErrorVal, -integer(HALF_RANGE));
    check_case(iErrorVal, oErrorVal, -integer(HALF_RANGE) - 1);
    check_case(iErrorVal, oErrorVal, integer(C_RANGE) - 1);
    check_case(iErrorVal, oErrorVal, -integer(C_RANGE));

    -- Pseudo-random coverage
    for i in 0 to 999 loop

      lfsr := lfsr_next(lfsr);
      errv := to_integer(signed(lfsr(BITNESS downto 0)));
      check_case(iErrorVal, oErrorVal, errv);

    end loop;

    if (errCount > 0) then
      report "tb_A9 RESULT: FAIL (" & integer'image(errCount) & " errors)"
        severity failure;
    else
      report "tb_A9 RESULT: PASS"
        severity note;
    end if;

    finish;

  end process stim;

end architecture bench;
