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
  constant MAX_VAL         : natural := CO_MAX_VAL_STD;

  signal iErrorVal         : signed(BITNESS downto 0);
  signal iPx               : unsigned(BITNESS - 1 downto 0);
  signal iSign             : std_logic;
  signal oRx               : unsigned(BITNESS - 1 downto 0);

  function compute_rx (
    px     : integer;
    sign_v : integer;
    errv   : integer
  ) return integer is

    variable rx : integer;

  begin

    rx := px + sign_v * errv;

    if (rx < 0) then
      rx := 0;
    elsif (rx > MAX_VAL) then
      rx := MAX_VAL;
    end if;

    return rx;

  end function compute_rx;

  procedure check_case (
    errv   : integer;
    px     : integer;
    sign_v : std_logic
  ) is

    variable signMult : integer;
    variable expRx    : integer;

  begin

    if (sign_v = CO_SIGN_POS) then
      signMult := 1;
    else
      signMult := - 1;
    end if;

    expRx := compute_rx(px, signMult, errv);

    check(oRx = to_unsigned(expRx, oRx'length),
          "A8 Rx mismatch: Err=" & integer'image(errv) &
          " Px=" & integer'image(px) &
          " exp=" & integer'image(expRx) &
          " got=" & integer'image(to_integer(oRx))
        );

  end procedure check_case;

  function lfsr_next (
    s : unsigned(31 downto 0)
  ) return unsigned is

    variable v   : unsigned(31 downto 0) := s;
    variable bit : std_logic;

  begin

    bit := v(31) xor v(21) xor v(1) xor v(0);
    v   := v(30 downto 0) & bit;
    return v;

  end function lfsr_next;

begin

  dut : entity work.a8_error_quantization(behavioral)

    generic map (
      BITNESS => BITNESS,
      MAX_VAL => MAX_VAL
    )
    port map (
      iErrorVal => iErrorVal,
      iPx       => iPx,
      iSign     => iSign,
      oRx       => oRx
    );

  stim : process is

    variable lfsr : unsigned(31 downto 0) := x"7D3A91E5";
    variable errv : integer;
    variable pxv  : integer;
    variable sign : std_logic;

  begin

    -- Initial values (no defaults — set explicitly here)
    iErrorVal <= (others => '0');
    iPx       <= (others => '0');
    iSign     <= CO_SIGN_POS;

    -- Directed cases
    iErrorVal <= to_signed(5, iErrorVal'length);
    iPx       <= to_unsigned(10, iPx'length);
    iSign     <= CO_SIGN_POS;
    wait for 1 ns;
    check_case(5, 10, CO_SIGN_POS);

    iErrorVal <= to_signed(-5, iErrorVal'length);
    iPx       <= to_unsigned(10, iPx'length);
    iSign     <= CO_SIGN_POS;
    wait for 1 ns;
    check_case(-5, 10, CO_SIGN_POS);

    iErrorVal <= to_signed(7, iErrorVal'length);
    iPx       <= to_unsigned(1, iPx'length);
    iSign     <= CO_SIGN_NEG;
    wait for 1 ns;
    check_case(7, 1, CO_SIGN_NEG);

    iErrorVal <= to_signed(-7, iErrorVal'length);
    iPx       <= to_unsigned(1, iPx'length);
    iSign     <= CO_SIGN_NEG;
    wait for 1 ns;
    check_case(-7, 1, CO_SIGN_NEG);

    iErrorVal <= to_signed(MAX_VAL, iErrorVal'length);
    iPx       <= to_unsigned(MAX_VAL, iPx'length);
    iSign     <= CO_SIGN_POS;
    wait for 1 ns;
    check_case(MAX_VAL, MAX_VAL, CO_SIGN_POS);

    iErrorVal <= to_signed(-MAX_VAL, iErrorVal'length);
    iPx       <= to_unsigned(10, iPx'length);
    iSign     <= CO_SIGN_NEG;
    wait for 1 ns;
    check_case(-MAX_VAL, 10, CO_SIGN_NEG);

    -- Px = 0, positive error -> Rx stays 0 (clamp)
    iErrorVal <= to_signed(-100, iErrorVal'length);
    iPx       <= to_unsigned(0, iPx'length);
    iSign     <= CO_SIGN_POS;
    wait for 1 ns;
    check_case(-100, 0, CO_SIGN_POS);

    -- Pseudo-random coverage
    for i in 0 to 999 loop

      lfsr      := lfsr_next(lfsr);
      errv      := to_integer(signed(lfsr(BITNESS downto 0)));
      lfsr      := lfsr_next(lfsr);
      pxv       := to_integer(unsigned(lfsr(BITNESS - 1 downto 0)));

      if (lfsr(0) = '1') then
        sign := CO_SIGN_POS;
      else
        sign := CO_SIGN_NEG;
      end if;

      iErrorVal <= to_signed(errv, iErrorVal'length);
      iPx       <= to_unsigned(pxv, iPx'length);
      iSign     <= sign;
      wait for 1 ns;
      check_case(errv, pxv, sign);

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
