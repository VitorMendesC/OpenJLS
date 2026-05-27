use work.Common.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.env.all;

entity tb_A13 is
end;

architecture bench of tb_A13 is
  shared variable err_count : natural := 0;

  procedure check(cond : boolean; msg : string) is
  begin
    if not cond then
      report msg severity error;
      err_count := err_count + 1;
    end if;
  end procedure;

  constant B_WIDTH : natural := 16;
  constant N_WIDTH : natural := CO_NQ_WIDTH_STD;
  constant C_WIDTH : natural := CO_CQ_WIDTH;

  signal iBq : signed(B_WIDTH - 1 downto 0) := (others => '0');
  signal iNq : unsigned(N_WIDTH - 1 downto 0) := (others => '0');
  signal iCq : signed(C_WIDTH - 1 downto 0) := (others => '0');
  signal oBq : signed(B_WIDTH - 1 downto 0);
  signal oCq : signed(C_WIDTH - 1 downto 0);

  function lfsr_next(s : unsigned(31 downto 0)) return unsigned is
    variable v   : unsigned(31 downto 0) := s;
    variable bit : std_logic;
  begin
    bit := v(31) xor v(21) xor v(1) xor v(0);
    v   := v(30 downto 0) & bit;
    return v;
  end function;

  procedure check_case(
    signal sBIn  : out signed;
    signal sNIn  : out unsigned;
    signal sCIn  : out signed;
    signal sBOut : in signed;
    signal sCOut : in signed;
    bq_val       : integer;
    nq_val       : integer;
    cq_val       : integer
  ) is
    variable exp_b : integer;
    variable exp_c : integer;
  begin
    sBIn <= to_signed(bq_val, sBIn'length);
    sNIn <= to_unsigned(nq_val, sNIn'length);
    sCIn <= to_signed(cq_val, sCIn'length);
    wait for 1 ns;

    if bq_val <= -nq_val then
      exp_b := bq_val + nq_val;
      if cq_val > CO_MIN_CQ then
        exp_c := cq_val - 1;
      else
        exp_c := cq_val;
      end if;
      if exp_b <= -nq_val then
        exp_b := -nq_val + 1;
      end if;
    elsif bq_val > 0 then
      exp_b := bq_val - nq_val;
      if cq_val < CO_MAX_CQ then
        exp_c := cq_val + 1;
      else
        exp_c := cq_val;
      end if;
      if exp_b > 0 then
        exp_b := 0;
      end if;
    else
      exp_b := bq_val;
      exp_c := cq_val;
    end if;

    check(sBOut = to_signed(exp_b, sBOut'length),
      "A13 Bq mismatch: Bq=" & integer'image(bq_val) &
      " Nq=" & integer'image(nq_val) &
      " Cq=" & integer'image(cq_val) &
      " exp=" & integer'image(exp_b) &
      " got=" & integer'image(to_integer(sBOut))
    );

    check(sCOut = to_signed(exp_c, sCOut'length),
      "A13 Cq mismatch: Bq=" & integer'image(bq_val) &
      " Nq=" & integer'image(nq_val) &
      " Cq=" & integer'image(cq_val) &
      " exp=" & integer'image(exp_c) &
      " got=" & integer'image(to_integer(sCOut))
    );
  end procedure;
begin
  dut : entity work.A13_update_bias
    generic map(
      B_WIDTH => B_WIDTH,
      N_WIDTH => N_WIDTH,
      C_WIDTH => C_WIDTH,
      MIN_C   => CO_MIN_CQ,
      MAX_C   => CO_MAX_CQ
    )
    port map(
      iBq => iBq,
      iNq => iNq,
      iCq => iCq,
      oBq => oBq,
      oCq => oCq
    );

  stim : process
    variable lfsr : unsigned(31 downto 0) := x"AF1C9B42";
    variable bqv  : integer;
    variable nqv  : integer;
    variable cqv  : integer;
  begin
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

    if err_count > 0 then
      report "tb_A13 RESULT: FAIL (" & integer'image(err_count) & " errors)" severity failure;
    else
      report "tb_A13 RESULT: PASS" severity note;
    end if;
    finish;
  end process;
end;
