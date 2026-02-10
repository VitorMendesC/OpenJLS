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

  signal iErr  : signed(BITNESS downto 0) := (others => '0');
  signal iPx   : unsigned(BITNESS - 1 downto 0) := (others => '0');
  signal iRI   : std_logic := '0';
  signal iRa   : unsigned(BITNESS - 1 downto 0) := (others => '0');
  signal iRb   : unsigned(BITNESS - 1 downto 0) := (others => '0');
  signal iIx   : unsigned(BITNESS - 1 downto 0) := (others => '0');

  signal oErrN0 : signed(BITNESS downto 0);
  signal oRxN0  : unsigned(BITNESS - 1 downto 0);
  signal oSignN0 : std_logic;

  signal oErrN2 : signed(BITNESS downto 0);
  signal oRxN2  : unsigned(BITNESS - 1 downto 0);
  signal oSignN2 : std_logic;

  function quantize(errv : integer; near_v : integer) return integer is
    constant scale : integer := (2 * near_v) + 1;
  begin
    if errv > 0 then
      return (errv + near_v) / scale;
    else
      return - (near_v - errv) / scale;
    end if;
  end function;

  procedure model(
    err_in  : integer;
    px      : integer;
    ri_type : integer;
    ra      : integer;
    rb      : integer;
    ix      : integer;
    near_v  : integer;
    err_out : out integer;
    rx_out  : out integer;
    sign_o  : out std_logic
  ) is
    constant range_v : integer := integer(MAX_VAL) + 1;
    constant scale   : integer := (2 * near_v) + 1;
    variable vErr    : integer;
    variable vRx     : integer;
    variable vSign   : std_logic;
    variable sign_m  : integer;
  begin
    vErr := err_in;

    if (ri_type = 0) and (ra > rb) then
      vErr  := -vErr;
      vSign := CO_SIGN_NEG;
    else
      vSign := CO_SIGN_POS;
    end if;

    if vSign = CO_SIGN_POS then
      sign_m := 1;
    else
      sign_m := -1;
    end if;

    if near_v > 0 then
      vErr := quantize(vErr, near_v);
      vRx  := px + sign_m * vErr * scale;
      if vRx < 0 then
        vRx := 0;
      elsif vRx > integer(MAX_VAL) then
        vRx := integer(MAX_VAL);
      end if;
    else
      vRx := ix;
    end if;

    -- Modulo reduction
    if vErr < 0 then
      vErr := vErr + range_v;
    end if;
    if vErr >= (range_v + 1) / 2 then
      vErr := vErr - range_v;
    end if;

    err_out := vErr;
    rx_out  := vRx;
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
    err_n0     : signed;
    rx_n0      : unsigned;
    sign_n0    : std_logic;
    err_n2     : signed;
    rx_n2      : unsigned;
    sign_n2    : std_logic
  ) is
    variable px      : integer;
    variable err_in  : integer;
    variable ri_int  : integer;
    variable exp_e0  : integer;
    variable exp_rx0 : integer;
    variable exp_s0  : std_logic;
    variable exp_e2  : integer;
    variable exp_rx2 : integer;
    variable exp_s2  : std_logic;
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

    model(err_in, px, ri_int, ra, rb, ix, 0, exp_e0, exp_rx0, exp_s0);
    model(err_in, px, ri_int, ra, rb, ix, 2, exp_e2, exp_rx2, exp_s2);

    check(err_n0 = to_signed(exp_e0, err_n0'length),
      "A19 NEAR=0 Err mismatch exp=" & integer'image(exp_e0) &
      " got=" & integer'image(to_integer(err_n0))
    );
    check(rx_n0 = to_unsigned(exp_rx0, rx_n0'length),
      "A19 NEAR=0 Rx mismatch exp=" & integer'image(exp_rx0) &
      " got=" & integer'image(to_integer(rx_n0))
    );
    check(sign_n0 = exp_s0, "A19 NEAR=0 Sign mismatch");

    check(err_n2 = to_signed(exp_e2, err_n2'length),
      "A19 NEAR=2 Err mismatch exp=" & integer'image(exp_e2) &
      " got=" & integer'image(to_integer(err_n2))
    );
    check(rx_n2 = to_unsigned(exp_rx2, rx_n2'length),
      "A19 NEAR=2 Rx mismatch exp=" & integer'image(exp_rx2) &
      " got=" & integer'image(to_integer(rx_n2))
    );
    check(sign_n2 = exp_s2, "A19 NEAR=2 Sign mismatch");
  end procedure;

begin

  dut_n0 : entity work.A19_run_interruption_error
    generic map(
      BITNESS => BITNESS,
      MAX_VAL => MAX_VAL,
      NEAR    => 0
    )
    port map(
      iErrval => iErr,
      iPx     => iPx,
      iRItype => iRI,
      iRa     => iRa,
      iRb     => iRb,
      iIx     => iIx,
      oErrval => oErrN0,
      oRx     => oRxN0,
      oSign   => oSignN0
    );

  dut_n2 : entity work.A19_run_interruption_error
    generic map(
      BITNESS => BITNESS,
      MAX_VAL => MAX_VAL,
      NEAR    => 2
    )
    port map(
      iErrval => iErr,
      iPx     => iPx,
      iRItype => iRI,
      iRa     => iRa,
      iRb     => iRb,
      iIx     => iIx,
      oErrval => oErrN2,
      oRx     => oRxN2,
      oSign   => oSignN2
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
    iIx  <= to_unsigned(60, iIx'length);
    iRI  <= '1';
    iPx  <= to_unsigned(50, iPx'length);
    iErr <= to_signed(10, iErr'length);
    wait for 1 ns;
    check_case(50, 20, 60, '1', oErrN0, oRxN0, oSignN0, oErrN2, oRxN2, oSignN2);

    iRa  <= to_unsigned(50, iRa'length);
    iRb  <= to_unsigned(20, iRb'length);
    iIx  <= to_unsigned(60, iIx'length);
    iRI  <= '0';
    iPx  <= to_unsigned(20, iPx'length);
    iErr <= to_signed(40, iErr'length);
    wait for 1 ns;
    check_case(50, 20, 60, '0', oErrN0, oRxN0, oSignN0, oErrN2, oRxN2, oSignN2);

    iRa  <= to_unsigned(200, iRa'length);
    iRb  <= to_unsigned(100, iRb'length);
    iIx  <= to_unsigned(10, iIx'length);
    iRI  <= '0';
    iPx  <= to_unsigned(100, iPx'length);
    iErr <= to_signed(-90, iErr'length);
    wait for 1 ns;
    check_case(200, 100, 10, '0', oErrN0, oRxN0, oSignN0, oErrN2, oRxN2, oSignN2); -- Ra > Rb, RItype=0

    iRa  <= to_unsigned(100, iRa'length);
    iRb  <= to_unsigned(200, iRb'length);
    iIx  <= to_unsigned(250, iIx'length);
    iRI  <= '0';
    iPx  <= to_unsigned(200, iPx'length);
    iErr <= to_signed(50, iErr'length);
    wait for 1 ns;
    check_case(100, 200, 250, '0', oErrN0, oRxN0, oSignN0, oErrN2, oRxN2, oSignN2); -- Ra < Rb, RItype=0

    -- Pseudo-random coverage
    for i in 0 to 199 loop
      lfsr := lfsr_next(lfsr);
      ra := to_integer(unsigned(lfsr(BITNESS - 1 downto 0)));
      lfsr := lfsr_next(lfsr);
      rb := to_integer(unsigned(lfsr(BITNESS - 1 downto 0)));
      lfsr := lfsr_next(lfsr);
      ix := to_integer(unsigned(lfsr(BITNESS - 1 downto 0)));
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
      iPx  <= to_unsigned(px_v, iPx'length);
      iErr <= to_signed(ix - px_v, iErr'length);
      iRa  <= to_unsigned(ra, iRa'length);
      iRb  <= to_unsigned(rb, iRb'length);
      iIx  <= to_unsigned(ix, iIx'length);
      iRI  <= ri;
      wait for 1 ns;
      check_case(ra, rb, ix, ri, oErrN0, oRxN0, oSignN0, oErrN2, oRxN2, oSignN2);
    end loop;

    if err_count > 0 then
      report "tb_A19 RESULT: FAIL (" & integer'image(err_count) & " errors)" severity failure;
    else
      report "tb_A19 RESULT: PASS" severity note;
    end if;
    finish;
  end process;

end;
