use work.common.all;

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use std.env.all;

entity tb_a12 is
end entity tb_a12;

architecture bench of tb_a12 is

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
  constant A_WIDTH         : natural := CO_AQ_WIDTH_STD;
  constant B_WIDTH         : natural := CO_BQ_WIDTH_STD;
  constant N_WIDTH         : natural := CO_NQ_WIDTH_STD;
  constant RESET           : natural := CO_RESET_STD;

  signal iErrorVal         : signed(BITNESS downto 0);
  signal iAq               : unsigned(A_WIDTH - 1 downto 0);
  signal iBq               : signed(B_WIDTH - 1 downto 0);
  signal iNq               : unsigned(N_WIDTH - 1 downto 0);

  signal oAqN0             : unsigned(A_WIDTH - 1 downto 0);
  signal oBqN0             : signed(B_WIDTH - 1 downto 0);
  signal oNqN0             : unsigned(N_WIDTH - 1 downto 0);

  signal oAqN2             : unsigned(A_WIDTH - 1 downto 0);
  signal oBqN2             : signed(B_WIDTH - 1 downto 0);
  signal oNqN2             : unsigned(N_WIDTH - 1 downto 0);

  function floor_div2 (
    v : integer
  ) return integer is
  begin

    if (v >= 0) then
      return v / 2;
    else
      return -((-v + 1) / 2);
    end if;

  end function floor_div2;

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

  procedure check_variant (
    signal saout : in unsigned;
    signal sbout : in signed;
    signal snout : in unsigned;
    err_val      : integer;
    aq_val       : natural;
    bq_val       : integer;
    nq_val       : natural;
    near_val     : natural;
    name_tag     : string
  ) is

    variable aqNew : integer;
    variable bqNew : integer;
    variable nqNew : integer;
    variable expA  : integer;
    variable expB  : integer;
    variable expN  : integer;

  begin

    aqNew := integer(aq_val) + abs(err_val);
    bqNew := bq_val + err_val * integer((2 * near_val) + 1);
    nqNew := integer(nq_val) + 1;

    if (nq_val = RESET) then
      expA := aqNew / 2;
      expB := floor_div2(bqNew);
      expN := integer(nq_val / 2) + 1;
    else
      expA := aqNew;
      expB := bqNew;
      expN := nqNew;
    end if;

    check(saout = to_unsigned(expA, saout'length),
          "A12 " & name_tag & " Aq mismatch: Err=" & integer'image(err_val) &
          " Aq=" & integer'image(integer(aq_val)) &
          " Bq=" & integer'image(bq_val) &
          " Nq=" & integer'image(integer(nq_val)) &
          " exp=" & integer'image(expA) &
          " got=" & integer'image(to_integer(saout))
        );

    check(sbout = to_signed(expB, sbout'length),
          "A12 " & name_tag & " Bq mismatch: Err=" & integer'image(err_val) &
          " Aq=" & integer'image(integer(aq_val)) &
          " Bq=" & integer'image(bq_val) &
          " Nq=" & integer'image(integer(nq_val)) &
          " exp=" & integer'image(expB) &
          " got=" & integer'image(to_integer(sbout))
        );

    check(snout = to_unsigned(expN, snout'length),
          "A12 " & name_tag & " Nq mismatch: Err=" & integer'image(err_val) &
          " Aq=" & integer'image(integer(aq_val)) &
          " Bq=" & integer'image(bq_val) &
          " Nq=" & integer'image(integer(nq_val)) &
          " exp=" & integer'image(expN) &
          " got=" & integer'image(to_integer(snout))
        );

  end procedure check_variant;

  procedure check_case (
    signal serr  : out signed;
    signal saqin : out unsigned;
    signal sbqin : out signed;
    signal snqin : out unsigned;
    signal saqn0 : in unsigned;
    signal sbqn0 : in signed;
    signal snqn0 : in unsigned;
    signal saqn2 : in unsigned;
    signal sbqn2 : in signed;
    signal snqn2 : in unsigned;
    err_val      : integer;
    aq_val       : natural;
    bq_val       : integer;
    nq_val       : natural
  ) is
  begin

    serr  <= to_signed(err_val, serr'length);
    saqin <= to_unsigned(aq_val, saqin'length);
    sbqin <= to_signed(bq_val, sbqin'length);
    snqin <= to_unsigned(nq_val, snqin'length);
    wait for 1 ns;

    check_variant(saqn0, sbqn0, snqn0, err_val, aq_val, bq_val, nq_val, 0, "NEAR=0");
    check_variant(saqn2, sbqn2, snqn2, err_val, aq_val, bq_val, nq_val, 2, "NEAR=2");

  end procedure check_case;

begin

  dut_n0 : entity work.a12_variables_update(rtl)

    generic map (
      BITNESS   => BITNESS,
      A_WIDTH   => A_WIDTH,
      B_WIDTH   => B_WIDTH,
      N_WIDTH   => N_WIDTH,
      RESET     => RESET,
      NEAR      => 0
    )
    port map (
      iErrorVal => iErrorVal,
      iAq       => iAq,
      iBq       => iBq,
      iNq       => iNq,
      oAq       => oAqN0,
      oBq       => oBqN0,
      oNq       => oNqN0
    );

  dut_n2 : entity work.a12_variables_update(rtl)

    generic map (
      BITNESS   => BITNESS,
      A_WIDTH   => A_WIDTH,
      B_WIDTH   => B_WIDTH,
      N_WIDTH   => N_WIDTH,
      RESET     => RESET,
      NEAR      => 2
    )
    port map (
      iErrorVal => iErrorVal,
      iAq       => iAq,
      iBq       => iBq,
      iNq       => iNq,
      oAq       => oAqN2,
      oBq       => oBqN2,
      oNq       => oNqN2
    );

  stim : process is

    variable lfsr : unsigned(31 downto 0);
    variable errv : integer;
    variable aqv  : natural;
    variable bqv  : integer;
    variable nqv  : natural;

  begin

    -- Initial values (no defaults — set explicitly here)
    iErrorVal <= (others => '0');
    iAq       <= (others => '0');
    iBq       <= (others => '0');
    iNq       <= (others => '0');

    -- Directed cases
    check_case(iErrorVal, iAq, iBq, iNq, oAqN0, oBqN0, oNqN0, oAqN2, oBqN2, oNqN2, 5, 10, -3, 1);
    check_case(iErrorVal, iAq, iBq, iNq, oAqN0, oBqN0, oNqN0, oAqN2, oBqN2, oNqN2, -7, 40, 12, 10);
    check_case(iErrorVal, iAq, iBq, iNq, oAqN0, oBqN0, oNqN0, oAqN2, oBqN2, oNqN2, 4, 20, 6, RESET);
    check_case(iErrorVal, iAq, iBq, iNq, oAqN0, oBqN0, oNqN0, oAqN2, oBqN2, oNqN2, -3, 21, 2, RESET);
    check_case(iErrorVal, iAq, iBq, iNq, oAqN0, oBqN0, oNqN0, oAqN2, oBqN2, oNqN2, 4095, 1000, -2000, 63);
    check_case(iErrorVal, iAq, iBq, iNq, oAqN0, oBqN0, oNqN0, oAqN2, oBqN2, oNqN2, -4096, 2000, 1500, RESET);

    -- Pseudo-random coverage
    for i in 0 to 999 loop

      lfsr := lfsr_next(lfsr);
      errv := to_integer(signed(lfsr(BITNESS downto 0)));

      lfsr := lfsr_next(lfsr);
      aqv  := to_integer(unsigned(lfsr(19 downto 0)));

      lfsr := lfsr_next(lfsr);
      bqv  := to_integer(signed(lfsr(20 downto 0)));

      lfsr := lfsr_next(lfsr);
      nqv  := (to_integer(unsigned(lfsr(7 downto 0))) mod RESET) + 1;

      if ((i mod 17) = 0) then
        nqv := RESET;
      end if;

      check_case(iErrorVal, iAq, iBq, iNq, oAqN0, oBqN0, oNqN0, oAqN2, oBqN2, oNqN2, errv, aqv, bqv, nqv);

    end loop;

    if (errCount > 0) then
      report "tb_A12 RESULT: FAIL (" & integer'image(errCount) & " errors)"
        severity failure;
    else
      report "tb_A12 RESULT: PASS"
        severity note;
    end if;

    finish;

  end process stim;

end architecture bench;
