use work.common.all;

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use std.env.all;

entity tb_a13 is
end entity tb_a13;

architecture bench of tb_a13 is

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

  constant B_WIDTH         : natural := 16;
  constant N_WIDTH         : natural := CO_NQ_WIDTH_STD;
  constant C_WIDTH         : natural := CO_CQ_WIDTH;

  signal iBq               : signed(B_WIDTH - 1 downto 0);
  signal iNq               : unsigned(N_WIDTH - 1 downto 0);
  signal iCq               : signed(C_WIDTH - 1 downto 0);
  signal oBq               : signed(B_WIDTH - 1 downto 0);
  signal oCq               : signed(C_WIDTH - 1 downto 0);

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
    signal sbin  : out signed;
    signal snin  : out unsigned;
    signal scin  : out signed;
    signal sbout : in signed;
    signal scout : in signed;
    bq_val       : integer;
    nq_val       : integer;
    cq_val       : integer
  ) is

    variable expB : integer;
    variable expC : integer;

  begin

    sbin <= to_signed(bq_val, sbin'length);
    snin <= to_unsigned(nq_val, snin'length);
    scin <= to_signed(cq_val, scin'length);
    wait for 1 ns;

    if (bq_val <= -nq_val) then
      expB := bq_val + nq_val;
      if (cq_val > CO_MIN_CQ) then
        expC := cq_val - 1;
      else
        expC := cq_val;
      end if;
      if (expB <= -nq_val) then
        expB := -nq_val + 1;
      end if;
    elsif (bq_val > 0) then
      expB := bq_val - nq_val;
      if (cq_val < CO_MAX_CQ) then
        expC := cq_val + 1;
      else
        expC := cq_val;
      end if;
      if (expB > 0) then
        expB := 0;
      end if;
    else
      expB := bq_val;
      expC := cq_val;
    end if;

    check(sbout = to_signed(expB, sbout'length),
          "A13 Bq mismatch: Bq=" & integer'image(bq_val) &
          " Nq=" & integer'image(nq_val) &
          " Cq=" & integer'image(cq_val) &
          " exp=" & integer'image(expB) &
          " got=" & integer'image(to_integer(sbout))
        );

    check(scout = to_signed(expC, scout'length),
          "A13 Cq mismatch: Bq=" & integer'image(bq_val) &
          " Nq=" & integer'image(nq_val) &
          " Cq=" & integer'image(cq_val) &
          " exp=" & integer'image(expC) &
          " got=" & integer'image(to_integer(scout))
        );

  end procedure check_case;

begin

  dut : entity work.a13_update_bias(rtl)

    generic map (
      B_WIDTH => B_WIDTH,
      N_WIDTH => N_WIDTH,
      C_WIDTH => C_WIDTH,
      MIN_C   => CO_MIN_CQ,
      MAX_C   => CO_MAX_CQ
    )
    port map (
      iBq     => iBq,
      iNq     => iNq,
      iCq     => iCq,
      oBq     => oBq,
      oCq     => oCq
    );

  stim : process is

    variable lfsr : unsigned(31 downto 0);
    variable bqv  : integer;
    variable nqv  : integer;
    variable cqv  : integer;

  begin

    -- Initial values (no defaults — set explicitly here)
    iBq <= (others => '0');
    iNq <= (others => '0');
    iCq <= (others => '0');

    -- Directed cases
    check_case(iBq, iNq, iCq, oBq, oCq, -5, 5, 10);
    check_case(iBq, iNq, iCq, oBq, oCq, -10, 4, 10);
    check_case(iBq, iNq, iCq, oBq, oCq, -4, 4, CO_MIN_CQ);
    check_case(iBq, iNq, iCq, oBq, oCq, 3, 5, 12);
    check_case(iBq, iNq, iCq, oBq, oCq, 10, 3, 12);
    check_case(iBq, iNq, iCq, oBq, oCq, 7, 3, CO_MAX_CQ);
    check_case(iBq, iNq, iCq, oBq, oCq, 0, 9, -30);
    check_case(iBq, iNq, iCq, oBq, oCq, -1, 9, -30);

    -- Pseudo-random coverage
    for i in 0 to 999 loop

      lfsr := lfsr_next(lfsr);
      bqv  := to_integer(signed(lfsr(15 downto 0)));

      lfsr := lfsr_next(lfsr);
      nqv  := (to_integer(unsigned(lfsr(5 downto 0))) mod 64) + 1;

      lfsr := lfsr_next(lfsr);
      cqv  := to_integer(signed(lfsr(7 downto 0)));

      check_case(iBq, iNq, iCq, oBq, oCq, bqv, nqv, cqv);

    end loop;

    if (errCount > 0) then
      report "tb_A13 RESULT: FAIL (" & integer'image(errCount) & " errors)"
        severity failure;
    else
      report "tb_A13 RESULT: PASS"
        severity note;
    end if;

    finish;

  end process stim;

end architecture bench;
