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

  constant ERROR_WIDTH     : natural := CO_ERROR_VALUE_WIDTH_STD;
  constant A_WIDTH         : natural := CO_AQ_WIDTH_STD;
  constant B_WIDTH         : natural := CO_BQ_WIDTH_STD;
  constant N_WIDTH         : natural := CO_NQ_WIDTH_STD;
  constant RESET           : natural := CO_RESET_STD;
  constant BITNESS         : natural := CO_BITNESS_STD;

  signal iErrorVal         : signed(ERROR_WIDTH - 1 downto 0);
  signal iAq               : unsigned(A_WIDTH - 1 downto 0);
  signal iBq               : signed(B_WIDTH - 1 downto 0);
  signal iNq               : unsigned(N_WIDTH - 1 downto 0);

  signal oAq               : unsigned(A_WIDTH - 1 downto 0);
  signal oBq               : signed(B_WIDTH - 1 downto 0);
  signal oNq               : unsigned(N_WIDTH - 1 downto 0);

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

    variable v   : unsigned(31 downto 0) := s;
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
    nq_val       : natural
  ) is

    variable aqNew : integer;
    variable bqNew : integer;
    variable nqNew : integer;
    variable expA  : integer;
    variable expB  : integer;
    variable expN  : integer;

  begin

    aqNew := integer(aq_val) + abs(err_val);
    bqNew := bq_val + err_val;
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
          "A12 Aq mismatch: Err=" & integer'image(err_val) &
          " Aq=" & integer'image(integer(aq_val)) &
          " Bq=" & integer'image(bq_val) &
          " Nq=" & integer'image(integer(nq_val)) &
          " exp=" & integer'image(expA) &
          " got=" & integer'image(to_integer(saout))
        );

    check(sbout = to_signed(expB, sbout'length),
          "A12 Bq mismatch: Err=" & integer'image(err_val) &
          " Aq=" & integer'image(integer(aq_val)) &
          " Bq=" & integer'image(bq_val) &
          " Nq=" & integer'image(integer(nq_val)) &
          " exp=" & integer'image(expB) &
          " got=" & integer'image(to_integer(sbout))
        );

    check(snout = to_unsigned(expN, snout'length),
          "A12 Nq mismatch: Err=" & integer'image(err_val) &
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
    signal saqout : in unsigned;
    signal sbqout : in signed;
    signal snqout : in unsigned;
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

    check_variant(saqout, sbqout, snqout, err_val, aq_val, bq_val, nq_val);

  end procedure check_case;

begin

  dut : entity work.a12_variables_update(rtl)

    generic map (
      ERROR_WIDTH => ERROR_WIDTH,
      A_WIDTH     => A_WIDTH,
      B_WIDTH     => B_WIDTH,
      N_WIDTH     => N_WIDTH,
      RESET       => RESET
    )
    port map (
      iErrorVal => iErrorVal,
      iAq       => iAq,
      iBq       => iBq,
      iNq       => iNq,
      oAq       => oAq,
      oBq       => oBq,
      oNq       => oNq
    );

  stim : process is

    variable lfsr : unsigned(31 downto 0) := x"A3C5E7F1";
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
    check_case(iErrorVal, iAq, iBq, iNq, oAq, oBq, oNq, 5, 10, -3, 1);
    check_case(iErrorVal, iAq, iBq, iNq, oAq, oBq, oNq, -7, 40, 12, 10);
    check_case(iErrorVal, iAq, iBq, iNq, oAq, oBq, oNq, 4, 20, 6, RESET);
    check_case(iErrorVal, iAq, iBq, iNq, oAq, oBq, oNq, -3, 21, 2, RESET);
    check_case(iErrorVal, iAq, iBq, iNq, oAq, oBq, oNq, 4095, 1000, -2000, 63);
    check_case(iErrorVal, iAq, iBq, iNq, oAq, oBq, oNq, -4096, 2000, 1500, RESET);

    -- Pseudo-random coverage
    for i in 0 to 999 loop

      lfsr := lfsr_next(lfsr);
      errv := to_integer(signed(lfsr(BITNESS - 1 downto 0)));         -- [-2^(bpp-1), 2^(bpp-1)-1]: modulo-reduced Errval range

      lfsr := lfsr_next(lfsr);
      aqv  := to_integer(unsigned(lfsr(A_WIDTH - 2 downto 0)));       -- leaves headroom for aq + |errv| within A_WIDTH

      lfsr := lfsr_next(lfsr);
      bqv  := to_integer(signed(lfsr(BITNESS - 1 downto 0)));         -- keeps bq + errv within B_WIDTH

      lfsr := lfsr_next(lfsr);
      nqv  := (to_integer(unsigned(lfsr(7 downto 0))) mod RESET) + 1;

      if ((i mod 17) = 0) then
        nqv := RESET;
      end if;

      check_case(iErrorVal, iAq, iBq, iNq, oAq, oBq, oNq, errv, aqv, bqv, nqv);

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
