use work.Common.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.env.all;

entity tb_A23 is
end;

architecture bench of tb_A23 is
  shared variable err_count : natural := 0;

  procedure check(cond : boolean; msg : string) is
  begin
    if not cond then
      report msg severity error;
      err_count := err_count + 1;
    end if;
  end procedure;

  constant A_WIDTH  : natural := CO_AQ_WIDTH_STD;
  constant N_WIDTH  : natural := CO_NQ_WIDTH_STD;
  constant ERR_W    : natural := CO_ERROR_VALUE_WIDTH_STD;
  constant ME_W     : natural := CO_MAPPED_ERROR_VAL_WIDTH_STD;
  constant RESET_V  : natural := CO_RESET_STD;

  signal iErr   : signed(ERR_W - 1 downto 0) := (others => '0');
  signal iEmErr : unsigned(ME_W - 1 downto 0) := (others => '0');
  signal iRI    : std_logic := '0';
  signal iAq    : unsigned(A_WIDTH - 1 downto 0) := (others => '0');
  signal iNq    : unsigned(N_WIDTH - 1 downto 0) := (others => '0');
  signal iNn    : unsigned(N_WIDTH - 1 downto 0) := (others => '0');

  signal oAq : unsigned(A_WIDTH - 1 downto 0);
  signal oNq : unsigned(N_WIDTH - 1 downto 0);
  signal oNn : unsigned(N_WIDTH - 1 downto 0);

  procedure model(
    errv   : integer;
    emerr  : integer;
    ri     : integer;
    aq     : integer;
    nq     : integer;
    nn     : integer;
    exp_a  : out integer;
    exp_n  : out integer;
    exp_nn : out integer
  ) is
    variable vA  : integer;
    variable vN  : integer;
    variable vNn : integer;
    variable vDelta : integer;
  begin
    vA  := aq;
    vN  := nq;
    vNn := nn;

    if errv < 0 then
      vNn := vNn + 1;
    end if;

    vDelta := (emerr + 1 - ri) / 2;
    vA := vA + vDelta;

    if vN = integer(RESET_V) then
      vA  := vA / 2;
      vN  := vN / 2;
      vNn := vNn / 2;
    end if;

    vN := vN + 1;

    exp_a  := vA;
    exp_n  := vN;
    exp_nn := vNn;
  end procedure;

  procedure check_case(
    errv, emerr, aq, nq, nn : integer;
    ri                     : std_logic;
    aq_o                   : unsigned;
    nq_o                   : unsigned;
    nn_o                   : unsigned
  ) is
    variable ri_i  : integer;
    variable exp_a : integer;
    variable exp_n : integer;
    variable exp_nn : integer;
  begin
    if ri = '1' then
      ri_i := 1;
    else
      ri_i := 0;
    end if;

    model(errv, emerr, ri_i, aq, nq, nn, exp_a, exp_n, exp_nn);

    check(aq_o = to_unsigned(exp_a, aq_o'length),
      "A23 Aq mismatch exp=" & integer'image(exp_a) &
      " got=" & integer'image(to_integer(aq_o))
    );
    check(nq_o = to_unsigned(exp_n, nq_o'length),
      "A23 Nq mismatch exp=" & integer'image(exp_n) &
      " got=" & integer'image(to_integer(nq_o))
    );
    check(nn_o = to_unsigned(exp_nn, nn_o'length),
      "A23 Nn mismatch exp=" & integer'image(exp_nn) &
      " got=" & integer'image(to_integer(nn_o))
    );
  end procedure;

begin

  dut : entity work.A23_run_interruption_update
    generic map(
      A_WIDTH             => A_WIDTH,
      N_WIDTH             => N_WIDTH,
      ERR_WIDTH           => ERR_W,
      MAPPED_ERRVAL_WIDTH => ME_W,
      RESET               => RESET_V
    )
    port map(
      iErrval   => iErr,
      iEMErrval => iEmErr,
      iRItype   => iRI,
      iAq       => iAq,
      iNq       => iNq,
      iNn       => iNn,
      oAq       => oAq,
      oNq       => oNq,
      oNn       => oNn
    );

  stim : process
  begin
    iErr   <= to_signed(-3, iErr'length);
    iEmErr <= to_unsigned(10, iEmErr'length);
    iRI    <= '0';
    iAq    <= to_unsigned(20, iAq'length);
    iNq    <= to_unsigned(RESET_V, iNq'length);
    iNn    <= to_unsigned(5, iNn'length);
    wait for 1 ns;
    check_case(-3, 10, 20, RESET_V, 5, '0', oAq, oNq, oNn);

    iErr   <= to_signed(4, iErr'length);
    iEmErr <= to_unsigned(7, iEmErr'length);
    iRI    <= '1';
    iAq    <= to_unsigned(50, iAq'length);
    iNq    <= to_unsigned(10, iNq'length);
    iNn    <= to_unsigned(2, iNn'length);
    wait for 1 ns;
    check_case(4, 7, 50, 10, 2, '1', oAq, oNq, oNn);

    iErr   <= to_signed(-1, iErr'length);
    iEmErr <= to_unsigned(5, iEmErr'length);
    iRI    <= '1';
    iAq    <= to_unsigned(100, iAq'length);
    iNq    <= to_unsigned(3, iNq'length);
    iNn    <= to_unsigned(1, iNn'length);
    wait for 1 ns;
    check_case(-1, 5, 100, 3, 1, '1', oAq, oNq, oNn);

    iErr   <= to_signed(1, iErr'length);
    iEmErr <= to_unsigned(0, iEmErr'length);
    iRI    <= '0';
    iAq    <= to_unsigned(0, iAq'length);
    iNq    <= to_unsigned(0, iNq'length);
    iNn    <= to_unsigned(0, iNn'length);
    wait for 1 ns;
    check_case(1, 0, 0, 0, 0, '0', oAq, oNq, oNn);

    if err_count > 0 then
      report "tb_A23 RESULT: FAIL (" & integer'image(err_count) & " errors)" severity failure;
    else
      report "tb_A23 RESULT: PASS" severity note;
    end if;
    finish;
  end process;

end;
