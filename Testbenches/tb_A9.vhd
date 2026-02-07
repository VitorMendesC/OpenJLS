library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_A9 is
end;

architecture bench of tb_A9 is
  -- Generics
  constant BITNESS    : natural range 8 to 16 := 12;
  constant MAX_VAL    : natural               := 2 ** BITNESS - 1;
  constant C_RANGE    : natural               := MAX_VAL + 1;
  constant HALF_RANGE : natural               := (C_RANGE + 1) / 2;

  -- Ports
  signal iErrorVal : signed (BITNESS downto 0);
  signal oErrorVal : signed (BITNESS downto 0);

  function modulo_reduce(errval : integer) return integer is
    variable v                    : integer := errval;
  begin
    if v < 0 then
      v := v + integer(C_RANGE);
    end if;
    if v >= integer(HALF_RANGE) then
      v := v - integer(C_RANGE);
    end if;
    return v;
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
    signal sIn  : out signed;
    signal sOut : in signed;
    errval      : integer
  ) is
    variable exp_v : integer;
  begin
    sIn <= to_signed(errval, sIn'length);
    wait for 1 ns;
    exp_v := modulo_reduce(errval);
    assert sOut = to_signed(exp_v, sOut'length)
    report "A9 mismatch: Errval=" & integer'image(errval) &
      " Exp=" & integer'image(exp_v) &
      " Got=" & integer'image(to_integer(sOut))
      severity failure;
  end procedure;
begin

  A9_modulo_reduction_inst : entity work.A9_modulo_reduction
    generic map(
      BITNESS => BITNESS
    )
    port map
    (
      iErrorVal => iErrorVal,
      oErrorVal => oErrorVal
    );

  stim : process
    variable lfsr : unsigned(31 downto 0) := x"4F1C3B2A";
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

    report "A9_tb completed" severity note;
    wait;
  end process;
end;
