use work.common.all;

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use std.env.all;

entity tb_a6 is
end entity tb_a6;

architecture bench of tb_a6 is

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
  constant BITNESS         : natural := 12;
  constant C_WIDTH         : natural := CO_CQ_WIDTH;
  constant MAX_VAL         : natural := 4095;
  constant MIN_CQ          : integer := CO_MIN_CQ;
  constant MAX_CQ          : integer := CO_MAX_CQ;
  -- Ports
  signal iPx               : unsigned (BITNESS - 1 downto 0);
  signal iSign             : std_logic;
  signal iCq               : signed (C_WIDTH - 1 downto 0);
  signal oPx               : unsigned (BITNESS - 1 downto 0);

  function predict (
    px : natural;
    sign : std_logic;
    cq : integer
  ) return natural is

    variable v : integer;

  begin

    if (sign = CO_SIGN_POS) then
      v := integer(px) + cq;
    else
      v := integer(px) - cq;
    end if;

    if (v > integer(MAX_VAL)) then
      return MAX_VAL;
    elsif (v < 0) then
      return 0;
    else
      return natural(v);
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
    signal spx   : out unsigned;
    signal ssign : out std_logic;
    signal scq   : out signed;
    signal sout  : in unsigned;
    px           : natural;
    sign         : std_logic;
    cq           : integer
  ) is

    variable expPx : natural;

  begin

    spx   <= to_unsigned(px, spx'length);
    ssign <= sign;
    scq   <= to_signed(cq, scq'length);
    wait for 1 ns;
    expPx := predict(px, sign, cq);
    check(sout = to_unsigned(expPx, sout'length),
          "Mismatch: Px=" & integer'image(px) &
          " Sign=" & std_logic'image(sign) &
          " Cq=" & integer'image(cq) &
          " exp=" & integer'image(expPx) &
          " got=" & integer'image(to_integer(sout))
        );

  end procedure check_case;

begin

  a6_prediction_correction_inst : entity work.a6_prediction_correction(behavioral)

    generic map (
      BITNESS => BITNESS,
      MAX_VAL => MAX_VAL
    )
    port map (
      iPx     => iPx,
      iSign   => iSign,
      iCq     => iCq,
      oPx     => oPx
    );

  stim : process is

    variable lfsr : unsigned(31 downto 0);
    variable px   : natural;
    variable cq   : integer;
    variable sign : std_logic;

  begin

    -- Directed edge cases
    check_case(iPx, iSign, iCq, oPx, 0, CO_SIGN_POS, 0);
    check_case(iPx, iSign, iCq, oPx, MAX_VAL, CO_SIGN_POS, 0);
    check_case(iPx, iSign, iCq, oPx, 0, CO_SIGN_NEG, 0);
    check_case(iPx, iSign, iCq, oPx, MAX_VAL, CO_SIGN_NEG, 0);
    check_case(iPx, iSign, iCq, oPx, MAX_VAL - 10, CO_SIGN_POS, 50);        -- add saturates
    check_case(iPx, iSign, iCq, oPx, 10, CO_SIGN_NEG, 50);                  -- sub underflows
    check_case(iPx, iSign, iCq, oPx, 100, CO_SIGN_POS, 50);                 -- add no sat
    check_case(iPx, iSign, iCq, oPx, 100, CO_SIGN_NEG, 50);                 -- sub no sat
    check_case(iPx, iSign, iCq, oPx, 0, CO_SIGN_POS, MAX_CQ);
    check_case(iPx, iSign, iCq, oPx, MAX_VAL, CO_SIGN_POS, MAX_CQ);
    check_case(iPx, iSign, iCq, oPx, 0, CO_SIGN_NEG, MAX_CQ);
    check_case(iPx, iSign, iCq, oPx, MAX_VAL, CO_SIGN_NEG, MAX_CQ);
    check_case(iPx, iSign, iCq, oPx, 0, CO_SIGN_POS, MIN_CQ);
    check_case(iPx, iSign, iCq, oPx, MAX_VAL, CO_SIGN_POS, MIN_CQ);
    check_case(iPx, iSign, iCq, oPx, 0, CO_SIGN_NEG, MIN_CQ);
    check_case(iPx, iSign, iCq, oPx, MAX_VAL, CO_SIGN_NEG, MIN_CQ);

    -- Pseudo-random coverage
    for i in 0 to 999 loop

      lfsr := lfsr_next(lfsr);
      px   := to_integer(lfsr(BITNESS - 1 downto 0));
      lfsr := lfsr_next(lfsr);
      cq   := to_integer(signed(lfsr(C_WIDTH - 1 downto 0)));
      lfsr := lfsr_next(lfsr);
      sign := lfsr(0);
      check_case(iPx, iSign, iCq, oPx, px, sign, cq);

    end loop;

    if (errCount > 0) then
      report "tb_A6 RESULT: FAIL (" & integer'image(errCount) & " errors)"
        severity failure;
    else
      report "tb_A6 RESULT: PASS"
        severity note;
    end if;

    finish;

  end process stim;

end architecture bench;
