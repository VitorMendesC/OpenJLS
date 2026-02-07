use work.Common.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_A12 is
end;

architecture bench of tb_A12 is
  constant BITNESS : natural := CO_BITNESS_STD;
  constant A_WIDTH : natural := CO_AQ_WIDTH_STD;
  constant B_WIDTH : natural := CO_BQ_WIDTH_STD;
  constant N_WIDTH : natural := CO_NQ_WIDTH_STD;
  constant RESET   : natural := CO_RESET_STD;

  signal iErrorVal : signed(BITNESS downto 0) := (others => '0');
  signal iAq       : unsigned(A_WIDTH - 1 downto 0) := (others => '0');
  signal iBq       : signed(B_WIDTH - 1 downto 0) := (others => '0');
  signal iNq       : unsigned(N_WIDTH - 1 downto 0) := (others => '0');

  signal oAqN0 : unsigned(A_WIDTH - 1 downto 0);
  signal oBqN0 : signed(B_WIDTH - 1 downto 0);
  signal oNqN0 : unsigned(N_WIDTH - 1 downto 0);

  signal oAqN2 : unsigned(A_WIDTH - 1 downto 0);
  signal oBqN2 : signed(B_WIDTH - 1 downto 0);
  signal oNqN2 : unsigned(N_WIDTH - 1 downto 0);

  function floor_div2(v : integer) return integer is
  begin
    if v >= 0 then
      return v / 2;
    else
      return -((-v + 1) / 2);
    end if;
  end function;

  function lfsr_next(s : unsigned(31 downto 0)) return unsigned is
    variable v   : unsigned(31 downto 0) := s;
    variable bit : std_logic;
  begin
    bit := v(31) xor v(21) xor v(1) xor v(0);
    v   := v(30 downto 0) & bit;
    return v;
  end function;

  procedure check_variant(
    signal sAOut : in unsigned;
    signal sBOut : in signed;
    signal sNOut : in unsigned;
    err_val      : integer;
    aq_val       : natural;
    bq_val       : integer;
    nq_val       : natural;
    near_val     : natural;
    name_tag     : string
  ) is
    variable aq_new : integer;
    variable bq_new : integer;
    variable nq_new : integer;
    variable exp_a  : integer;
    variable exp_b  : integer;
    variable exp_n  : integer;
  begin
    aq_new := integer(aq_val) + abs(err_val);
    bq_new := bq_val + err_val * integer((2 * near_val) + 1);
    nq_new := integer(nq_val) + 1;

    if nq_val = RESET then
      exp_a := aq_new / 2;
      exp_b := floor_div2(bq_new);
      exp_n := integer(nq_val / 2) + 1;
    else
      exp_a := aq_new;
      exp_b := bq_new;
      exp_n := nq_new;
    end if;

    assert sAOut = to_unsigned(exp_a, sAOut'length)
      report "A12 " & name_tag & " Aq mismatch: Err=" & integer'image(err_val) &
             " Aq=" & integer'image(integer(aq_val)) &
             " Bq=" & integer'image(bq_val) &
             " Nq=" & integer'image(integer(nq_val)) &
             " exp=" & integer'image(exp_a) &
             " got=" & integer'image(to_integer(sAOut))
      severity failure;

    assert sBOut = to_signed(exp_b, sBOut'length)
      report "A12 " & name_tag & " Bq mismatch: Err=" & integer'image(err_val) &
             " Aq=" & integer'image(integer(aq_val)) &
             " Bq=" & integer'image(bq_val) &
             " Nq=" & integer'image(integer(nq_val)) &
             " exp=" & integer'image(exp_b) &
             " got=" & integer'image(to_integer(sBOut))
      severity failure;

    assert sNOut = to_unsigned(exp_n, sNOut'length)
      report "A12 " & name_tag & " Nq mismatch: Err=" & integer'image(err_val) &
             " Aq=" & integer'image(integer(aq_val)) &
             " Bq=" & integer'image(bq_val) &
             " Nq=" & integer'image(integer(nq_val)) &
             " exp=" & integer'image(exp_n) &
             " got=" & integer'image(to_integer(sNOut))
      severity failure;
  end procedure;

  procedure check_case(
    signal sErr   : out signed;
    signal sAqIn  : out unsigned;
    signal sBqIn  : out signed;
    signal sNqIn  : out unsigned;
    signal sAqN0  : in unsigned;
    signal sBqN0  : in signed;
    signal sNqN0  : in unsigned;
    signal sAqN2  : in unsigned;
    signal sBqN2  : in signed;
    signal sNqN2  : in unsigned;
    err_val       : integer;
    aq_val        : natural;
    bq_val        : integer;
    nq_val        : natural
  ) is
  begin
    sErr  <= to_signed(err_val, sErr'length);
    sAqIn <= to_unsigned(aq_val, sAqIn'length);
    sBqIn <= to_signed(bq_val, sBqIn'length);
    sNqIn <= to_unsigned(nq_val, sNqIn'length);
    wait for 1 ns;

    check_variant(sAqN0, sBqN0, sNqN0, err_val, aq_val, bq_val, nq_val, 0, "NEAR=0");
    check_variant(sAqN2, sBqN2, sNqN2, err_val, aq_val, bq_val, nq_val, 2, "NEAR=2");
  end procedure;
begin
  dut_n0 : entity work.A12_variables_update
    generic map(
      BITNESS => BITNESS,
      A_WIDTH => A_WIDTH,
      B_WIDTH => B_WIDTH,
      N_WIDTH => N_WIDTH,
      RESET   => RESET,
      NEAR    => 0
    )
    port map(
      iErrorVal => iErrorVal,
      iAq       => iAq,
      iBq       => iBq,
      iNq       => iNq,
      oAq       => oAqN0,
      oBq       => oBqN0,
      oNq       => oNqN0
    );

  dut_n2 : entity work.A12_variables_update
    generic map(
      BITNESS => BITNESS,
      A_WIDTH => A_WIDTH,
      B_WIDTH => B_WIDTH,
      N_WIDTH => N_WIDTH,
      RESET   => RESET,
      NEAR    => 2
    )
    port map(
      iErrorVal => iErrorVal,
      iAq       => iAq,
      iBq       => iBq,
      iNq       => iNq,
      oAq       => oAqN2,
      oBq       => oBqN2,
      oNq       => oNqN2
    );

  stim : process
    variable lfsr : unsigned(31 downto 0) := x"34DA7C19";
    variable errv : integer;
    variable aqv  : natural;
    variable bqv  : integer;
    variable nqv  : natural;
  begin
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
      if (i mod 17) = 0 then
        nqv := RESET;
      end if;

      check_case(iErrorVal, iAq, iBq, iNq, oAqN0, oBqN0, oNqN0, oAqN2, oBqN2, oNqN2, errv, aqv, bqv, nqv);
    end loop;

    report "tb_A12 completed" severity note;
    wait;
  end process;
end;
