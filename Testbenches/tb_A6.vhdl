
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.Common.all;

entity tb_A6 is
end;

architecture bench of tb_A6 is
  -- Clock period
  constant clk_period : time := 5 ns;
  -- Generics
  constant BITNESS : natural := 12;
  constant C_WIDTH : natural := CO_CQ_WIDTH;
  constant MAX_VAL : natural := 4095;
  constant MIN_CQ  : integer := CO_MIN_CQ;
  constant MAX_CQ  : integer := CO_MAX_CQ;
  -- Ports
  signal iPx   : unsigned (BITNESS - 1 downto 0);
  signal iSign : std_logic;
  signal iCq   : signed (C_WIDTH - 1 downto 0);
  signal oPx   : unsigned (BITNESS - 1 downto 0);

  function predict(px : natural; sign : std_logic; cq : integer) return natural is
    variable v : integer;
  begin
    if sign = '0' then
      v := integer(px) + cq;
    else
      v := integer(px) - cq;
    end if;

    if v > integer(MAX_VAL) then
      return MAX_VAL;
    elsif v < 0 then
      return 0;
    else
      return natural(v);
    end if;
  end function;

  function lfsr_next(s : unsigned(31 downto 0)) return unsigned is
    variable v           : unsigned(31 downto 0) := s;
    variable bit         : std_logic;
  begin
    bit := v(31) xor v(21) xor v(1) xor v(0);
    v   := v(30 downto 0) & bit;
    return v;
  end function;

  procedure check_case(
    signal sPx   : out unsigned;
    signal sSign : out std_logic;
    signal sCq   : out signed;
    signal sOut  : in unsigned;
    px           : natural;
    sign         : std_logic;
    cq           : integer
  ) is
    variable exp_px : natural;
  begin
    sPx   <= to_unsigned(px, sPx'length);
    sSign <= sign;
    sCq   <= to_signed(cq, sCq'length);
    wait for 1 ns;
    exp_px := predict(px, sign, cq);
    assert sOut = to_unsigned(exp_px, sOut'length)
    report "Mismatch: Px=" & integer'image(px) &
      " Sign=" & std_logic'image(sign) &
      " Cq=" & integer'image(cq) &
      " exp=" & integer'image(exp_px) &
      " got=" & integer'image(to_integer(sOut))
      severity error;
  end procedure;
begin

  A6_prediction_correction_inst : entity work.A6_prediction_correction
    generic map(
      BITNESS => BITNESS,
      MAX_VAL => MAX_VAL
    )
    port map
    (
      iPx   => iPx,
      iSign => iSign,
      iCq   => iCq,
      oPx   => oPx
    );
  -- clk <= not clk after clk_period/2;

  stim : process
    variable lfsr : unsigned(31 downto 0) := x"6C1A9F2D";
    variable px   : natural;
    variable cq   : integer;
    variable sign : std_logic;
  begin
    -- Directed edge cases
    check_case(iPx, iSign, iCq, oPx, 0, '0', 0);
    check_case(iPx, iSign, iCq, oPx, MAX_VAL, '0', 0);
    check_case(iPx, iSign, iCq, oPx, 0, '1', 0);
    check_case(iPx, iSign, iCq, oPx, MAX_VAL, '1', 0);
    check_case(iPx, iSign, iCq, oPx, MAX_VAL - 10, '0', 50); -- add saturates
    check_case(iPx, iSign, iCq, oPx, 10, '1', 50); -- sub underflows
    check_case(iPx, iSign, iCq, oPx, 100, '0', 50); -- add no sat
    check_case(iPx, iSign, iCq, oPx, 100, '1', 50); -- sub no sat
    check_case(iPx, iSign, iCq, oPx, 0, '0', MAX_CQ);
    check_case(iPx, iSign, iCq, oPx, MAX_VAL, '0', MAX_CQ);
    check_case(iPx, iSign, iCq, oPx, 0, '1', MAX_CQ);
    check_case(iPx, iSign, iCq, oPx, MAX_VAL, '1', MAX_CQ);
    check_case(iPx, iSign, iCq, oPx, 0, '0', MIN_CQ);
    check_case(iPx, iSign, iCq, oPx, MAX_VAL, '0', MIN_CQ);
    check_case(iPx, iSign, iCq, oPx, 0, '1', MIN_CQ);
    check_case(iPx, iSign, iCq, oPx, MAX_VAL, '1', MIN_CQ);

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

    report "tb_A6 completed" severity note;
    wait;
  end process;
end;
