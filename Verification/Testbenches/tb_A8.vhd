use work.common.all;

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use std.env.all;

entity tb_a8 is
end entity tb_a8;

architecture bench of tb_a8 is

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

  constant BITNESS         : natural := CO_BITNESS_STD;
  constant MAX_VAL         : natural := 2 ** BITNESS - 1;

  signal iErr              : signed(BITNESS downto 0);
  signal iPx               : unsigned(BITNESS - 1 downto 0);
  signal iSign             : std_logic;

  signal oErrN0            : signed(BITNESS downto 0);
  signal oRxN0             : unsigned(BITNESS - 1 downto 0);
  signal oErrN2            : signed(BITNESS downto 0);
  signal oRxN2             : unsigned(BITNESS - 1 downto 0);

  function quantize (
    errv : integer;
    near_v : integer
  ) return integer is

    constant SCALE : integer := (2 * near_v) + 1;
    variable q     : integer;

  begin

    if (errv > 0) then
      q := (errv + near_v) / SCALE;
    else
      q := - (near_v - errv) / SCALE;
    end if;

    return q;

  end function quantize;

  function compute_rx (
    px : integer;
    sign_v : integer;
    qerr : integer;
    near_v : integer
  ) return integer is

    constant SCALE : integer := (2 * near_v) + 1;
    variable rx    : integer;

  begin

    rx := px + sign_v * qerr * SCALE;

    if (rx < 0) then
      rx := 0;
    elsif (rx > integer(MAX_VAL)) then
      rx := integer(MAX_VAL);
    end if;

    return rx;

  end function compute_rx;

  procedure check_case (
    errv     : integer;
    px       : integer;
    sign_v   : std_logic;
    err0_sig : signed;
    rx0_sig  : unsigned;
    err2_sig : signed;
    rx2_sig  : unsigned
  ) is

    variable signMult : integer;
    variable q0       : integer;
    variable q2       : integer;
    variable rx0Val   : integer;
    variable rx2Val   : integer;

  begin

    if (sign_v = CO_SIGN_POS) then
      signMult := 1;
    else
      signMult := -1;
    end if;

    q0     := quantize(errv, 0);
    q2     := quantize(errv, 2);
    rx0Val := compute_rx(px, signMult, q0, 0);
    rx2Val := compute_rx(px, signMult, q2, 2);

    check(err0_sig = to_signed(q0, err0_sig'length),
          "A8 NEAR=0 Err mismatch: Err=" & integer'image(errv) &
          " Px=" & integer'image(px) &
          " exp=" & integer'image(q0) &
          " got=" & integer'image(to_integer(err0_sig))
        );
    check(rx0_sig = to_unsigned(rx0Val, rx0_sig'length),
          "A8 NEAR=0 Rx mismatch: Err=" & integer'image(errv) &
          " Px=" & integer'image(px) &
          " exp=" & integer'image(rx0Val) &
          " got=" & integer'image(to_integer(rx0_sig))
        );

    check(err2_sig = to_signed(q2, err2_sig'length),
          "A8 NEAR=2 Err mismatch: Err=" & integer'image(errv) &
          " Px=" & integer'image(px) &
          " exp=" & integer'image(q2) &
          " got=" & integer'image(to_integer(err2_sig))
        );
    check(rx2_sig = to_unsigned(rx2Val, rx2_sig'length),
          "A8 NEAR=2 Rx mismatch: Err=" & integer'image(errv) &
          " Px=" & integer'image(px) &
          " exp=" & integer'image(rx2Val) &
          " got=" & integer'image(to_integer(rx2_sig))
        );

  end procedure check_case;

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

begin

  dut_n0 : entity work.a8_error_quantization(behavioral)

    generic map (
      BITNESS   => BITNESS,
      MAX_VAL   => MAX_VAL,
      NEAR      => 0
    )
    port map (
      iErrorVal => iErr,
      iPx       => iPx,
      iSign     => iSign,
      oErrorVal => oErrN0,
      oRx       => oRxN0
    );

  dut_n2 : entity work.a8_error_quantization(behavioral)

    generic map (
      BITNESS   => BITNESS,
      MAX_VAL   => MAX_VAL,
      NEAR      => 2
    )
    port map (
      iErrorVal => iErr,
      iPx       => iPx,
      iSign     => iSign,
      oErrorVal => oErrN2,
      oRx       => oRxN2
    );

  stim : process is

    variable lfsr : unsigned(31 downto 0);
    variable errv : integer;
    variable pxv  : integer;
    variable sign : std_logic;

  begin

    -- Initial values (no defaults — set explicitly here)
    iErr  <= (others => '0');
    iPx   <= (others => '0');
    iSign <= CO_SIGN_POS;

    -- Directed cases
    iErr  <= to_signed(5, iErr'length);
    iPx   <= to_unsigned(10, iPx'length);
    iSign <= CO_SIGN_POS;
    wait for 1 ns;
    check_case(5, 10, CO_SIGN_POS, oErrN0, oRxN0, oErrN2, oRxN2);

    iErr  <= to_signed(-5, iErr'length);
    iPx   <= to_unsigned(10, iPx'length);
    iSign <= CO_SIGN_POS;
    wait for 1 ns;
    check_case(-5, 10, CO_SIGN_POS, oErrN0, oRxN0, oErrN2, oRxN2);

    iErr  <= to_signed(7, iErr'length);
    iPx   <= to_unsigned(1, iPx'length);
    iSign <= CO_SIGN_NEG;
    wait for 1 ns;
    check_case(7, 1, CO_SIGN_NEG, oErrN0, oRxN0, oErrN2, oRxN2);

    iErr  <= to_signed(-7, iErr'length);
    iPx   <= to_unsigned(1, iPx'length);
    iSign <= CO_SIGN_NEG;
    wait for 1 ns;
    check_case(-7, 1, CO_SIGN_NEG, oErrN0, oRxN0, oErrN2, oRxN2);

    iErr  <= to_signed(4095, iErr'length);
    iPx   <= to_unsigned(4090, iPx'length);
    iSign <= CO_SIGN_POS;
    wait for 1 ns;
    check_case(4095, 4090, CO_SIGN_POS, oErrN0, oRxN0, oErrN2, oRxN2);

    iErr  <= to_signed(-4096, iErr'length);
    iPx   <= to_unsigned(10, iPx'length);
    iSign <= CO_SIGN_NEG;
    wait for 1 ns;
    check_case(-4096, 10, CO_SIGN_NEG, oErrN0, oRxN0, oErrN2, oRxN2);

    -- Pseudo-random coverage
    for i in 0 to 299 loop

      lfsr := lfsr_next(lfsr);
      errv := to_integer(signed(lfsr(BITNESS downto 0)));
      lfsr := lfsr_next(lfsr);
      pxv  := to_integer(unsigned(lfsr(BITNESS - 1 downto 0)));

      if (lfsr(0) = '1') then
        sign := CO_SIGN_POS;
      else
        sign := CO_SIGN_NEG;
      end if;

      iErr  <= to_signed(errv, iErr'length);
      iPx   <= to_unsigned(pxv, iPx'length);
      iSign <= sign;
      wait for 1 ns;
      check_case(errv, pxv, sign, oErrN0, oRxN0, oErrN2, oRxN2);

    end loop;

    if (errCount > 0) then
      report "tb_A8 RESULT: FAIL (" & integer'image(errCount) & " errors)"
        severity failure;
    else
      report "tb_A8 RESULT: PASS"
        severity note;
    end if;

    finish;

  end process stim;

end architecture bench;
