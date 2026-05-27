use work.Common.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.env.all;

entity tb_A19 is
end;

architecture bench of tb_A19 is
  shared variable err_count : natural := 0;

  procedure check(cond : boolean; msg : string) is
  begin
    if not cond then
      report msg severity error;
      err_count := err_count + 1;
    end if;
  end procedure;

  constant BITNESS : natural := CO_BITNESS_STD;
  constant MAX_VAL : natural := CO_MAX_VAL_STD;

  signal iErr : signed(BITNESS downto 0)       := (others => '0');
  signal iRI  : std_logic                      := '0';
  signal iRa  : unsigned(BITNESS - 1 downto 0) := (others => '0');
  signal iRb  : unsigned(BITNESS - 1 downto 0) := (others => '0');

  signal oErr  : signed(BITNESS downto 0);
  signal oSign : std_logic;

  -- Lossless reference model (NEAR = 0)
  procedure model(
    err_in  : integer;
    ri_type : integer;
    ra      : integer;
    rb      : integer;
    err_out : out integer;
    sign_o  : out std_logic
  ) is
    constant range_v : integer := integer(MAX_VAL) + 1;
    variable vErr    : integer;
    variable vSign   : std_logic;
  begin
    vErr := err_in;

    if ri_type = 0 and ra > rb then
      vErr  := -vErr;
      vSign := CO_SIGN_NEG;
    else
      vSign := CO_SIGN_POS;
    end if;

    -- Modulo reduction
    if vErr < 0 then
      vErr := vErr + range_v;
    end if;
    if vErr >= (range_v + 1) / 2 then
      vErr := vErr - range_v;
    end if;

    err_out := vErr;
    sign_o  := vSign;
  end procedure;

  function lfsr_next(s : unsigned(31 downto 0)) return unsigned is
    variable v   : unsigned(31 downto 0) := s;
    variable bit : std_logic;
  begin
    bit := v(31) xor v(21) xor v(1) xor v(0);
    v   := v(30 downto 0) & bit;
    return v;
  end function;

  procedure check_case(
    ra, rb, ix : integer;
    ri         : std_logic;
    err_out    : signed;
    sign_out   : std_logic
  ) is
    variable px     : integer;
    variable err_in : integer;
    variable ri_int : integer;
    variable exp_e  : integer;
    variable exp_s  : std_logic;
  begin
    if ri = '1' then
      px := ra;
    else
      px := rb;
    end if;

    err_in := ix - px;

    if ri = '1' then
      ri_int := 1;
    else
      ri_int := 0;
    end if;

    model(err_in, ri_int, ra, rb, exp_e, exp_s);

    check(err_out = to_signed(exp_e, err_out'length),
      "A19 Err mismatch exp=" & integer'image(exp_e) &
      " got=" & integer'image(to_integer(err_out))
    );
    check(sign_out = exp_s, "A19 Sign mismatch");
  end procedure;

begin

  dut : entity work.A19_run_interruption_error
    generic map(
      BITNESS => BITNESS,
      MAX_VAL => MAX_VAL
    )
    port map(
      iErrval => iErr,
      iRItype => iRI,
      iRa     => iRa,
      iRb     => iRb,
      oErrval => oErr,
      oSign   => oSign
    );

  stim : process
    variable lfsr : unsigned(31 downto 0) := x"A5C3F192";
    variable ra   : integer;
    variable rb   : integer;
    variable ix   : integer;
    variable ri   : std_logic;
    variable px_v : integer;
  begin
    -- Directed cases
    iRa  <= to_unsigned(50, iRa'length);
    iRb  <= to_unsigned(20, iRb'length);
    iRI  <= '1';
    iErr <= to_signed(10, iErr'length);
    wait for 1 ns;
    check_case(50, 20, 60, '1', oErr, oSign);

    iRa  <= to_unsigned(50, iRa'length);
    iRb  <= to_unsigned(20, iRb'length);
    iRI  <= '0';
    iErr <= to_signed(40, iErr'length);
    wait for 1 ns;
    check_case(50, 20, 60, '0', oErr, oSign);

    -- Ra > Rb, RItype=0 → sign negated
    iRa  <= to_unsigned(200, iRa'length);
    iRb  <= to_unsigned(100, iRb'length);
    iRI  <= '0';
    iErr <= to_signed(-90, iErr'length);
    wait for 1 ns;
    check_case(200, 100, 10, '0', oErr, oSign);

    -- Ra < Rb, RItype=0 → sign positive
    iRa  <= to_unsigned(100, iRa'length);
    iRb  <= to_unsigned(200, iRb'length);
    iRI  <= '0';
    iErr <= to_signed(50, iErr'length);
    wait for 1 ns;
    check_case(100, 200, 250, '0', oErr, oSign);

    -- Pseudo-random coverage
    for i in 0 to 199 loop
      lfsr := lfsr_next(lfsr);
      ra   := to_integer(unsigned(lfsr(BITNESS - 1 downto 0)));
      lfsr := lfsr_next(lfsr);
      rb   := to_integer(unsigned(lfsr(BITNESS - 1 downto 0)));
      lfsr := lfsr_next(lfsr);
      ix   := to_integer(unsigned(lfsr(BITNESS - 1 downto 0)));
      if lfsr(0) = '1' then
        ri := '1';
      else
        ri := '0';
      end if;
      if ri = '1' then
        px_v := ra;
      else
        px_v := rb;
      end if;
      iErr <= to_signed(ix - px_v, iErr'length);
      iRa  <= to_unsigned(ra, iRa'length);
      iRb  <= to_unsigned(rb, iRb'length);
      iRI  <= ri;
      wait for 1 ns;
      check_case(ra, rb, ix, ri, oErr, oSign);
    end loop;

    if err_count > 0 then
      report "tb_A19 RESULT: FAIL (" & integer'image(err_count) & " errors)" severity failure;
    else
      report "tb_A19 RESULT: PASS" severity note;
    end if;
    finish;
  end process;

end;
