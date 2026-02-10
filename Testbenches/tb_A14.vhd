use work.Common.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.env.all;

entity tb_A14 is
end;

architecture bench of tb_A14 is
  shared variable err_count : natural := 0;

  procedure check(cond : boolean; msg : string) is
  begin
    if not cond then
      report msg severity error;
      err_count := err_count + 1;
    end if;
  end procedure;

  constant BITNESS       : natural := CO_BITNESS_STD;
  constant RUN_CNT_WIDTH : natural := 8;
  constant NEAR_VAL      : natural := 1;

  signal iRa      : unsigned(BITNESS - 1 downto 0) := (others => '0');
  signal iIx      : unsigned(BITNESS - 1 downto 0) := (others => '0');
  signal iRunCnt  : unsigned(RUN_CNT_WIDTH - 1 downto 0) := (others => '0');
  signal iEOL     : std_logic := '0';
  signal oRunCnt  : unsigned(RUN_CNT_WIDTH - 1 downto 0);
  signal oRx      : unsigned(BITNESS - 1 downto 0);
  signal oRunHit  : std_logic;
  signal oCont    : std_logic;

  procedure check_case(
    ra, ix, rc : integer;
    eol        : std_logic;
    run_cnt_o  : unsigned;
    rx_o       : unsigned;
    run_hit_o  : std_logic;
    cont_o     : std_logic
  ) is
    variable diff      : integer;
    variable exp_hit   : std_logic;
    variable exp_cnt   : integer;
    variable exp_cont  : std_logic;
  begin
    diff := abs(ix - ra);
    if diff <= integer(NEAR_VAL) then
      exp_hit := '1';
      exp_cnt := rc + 1;
    else
      exp_hit := '0';
      exp_cnt := rc;
    end if;

    if (exp_hit = '1') and (eol = '0') then
      exp_cont := '1';
    else
      exp_cont := '0';
    end if;

    check(run_hit_o = exp_hit,
      "A14 RunHit mismatch: Ra=" & integer'image(ra) &
      " Ix=" & integer'image(ix) &
      " exp=" & std_logic'image(exp_hit) &
      " got=" & std_logic'image(run_hit_o)
    );
    check(run_cnt_o = to_unsigned(exp_cnt, run_cnt_o'length),
      "A14 RunCnt mismatch: exp=" & integer'image(exp_cnt) &
      " got=" & integer'image(to_integer(run_cnt_o))
    );
    check(cont_o = exp_cont,
      "A14 RunContinue mismatch: exp=" & std_logic'image(exp_cont) &
      " got=" & std_logic'image(cont_o)
    );
    check(rx_o = to_unsigned(ra, rx_o'length), "A14 Rx mismatch");
  end procedure;

begin

  dut : entity work.A14_run_length_determination
    generic map(
      BITNESS       => BITNESS,
      RUN_CNT_WIDTH => RUN_CNT_WIDTH,
      NEAR          => NEAR_VAL
    )
    port map(
      iRa          => iRa,
      iIx          => iIx,
      iRunCnt      => iRunCnt,
      iEOL         => iEOL,
      oRunCnt      => oRunCnt,
      oRx          => oRx,
      oRunHit      => oRunHit,
      oRunContinue => oCont
    );

  stim : process
  begin
    iRa     <= to_unsigned(10, iRa'length);
    iIx     <= to_unsigned(10, iIx'length);
    iRunCnt <= to_unsigned(0, iRunCnt'length);
    iEOL    <= '0';
    wait for 1 ns;
    check_case(10, 10, 0, '0', oRunCnt, oRx, oRunHit, oCont);

    iRa     <= to_unsigned(10, iRa'length);
    iIx     <= to_unsigned(11, iIx'length);
    iRunCnt <= to_unsigned(5, iRunCnt'length);
    iEOL    <= '0';
    wait for 1 ns;
    check_case(10, 11, 5, '0', oRunCnt, oRx, oRunHit, oCont);

    iRa     <= to_unsigned(10, iRa'length);
    iIx     <= to_unsigned(12, iIx'length);
    iRunCnt <= to_unsigned(5, iRunCnt'length);
    iEOL    <= '0';
    wait for 1 ns;
    check_case(10, 12, 5, '0', oRunCnt, oRx, oRunHit, oCont);

    iRa     <= to_unsigned(10, iRa'length);
    iIx     <= to_unsigned(10, iIx'length);
    iRunCnt <= to_unsigned(3, iRunCnt'length);
    iEOL    <= '1';
    wait for 1 ns;
    check_case(10, 10, 3, '1', oRunCnt, oRx, oRunHit, oCont);

    iRa     <= to_unsigned(100, iRa'length);
    iIx     <= to_unsigned(98, iIx'length);
    iRunCnt <= to_unsigned(7, iRunCnt'length);
    iEOL    <= '0';
    wait for 1 ns;
    check_case(100, 98, 7, '0', oRunCnt, oRx, oRunHit, oCont);

    iRa     <= to_unsigned(100, iRa'length);
    iIx     <= to_unsigned(102, iIx'length);
    iRunCnt <= to_unsigned(7, iRunCnt'length);
    iEOL    <= '1';
    wait for 1 ns;
    check_case(100, 102, 7, '1', oRunCnt, oRx, oRunHit, oCont);

    if err_count > 0 then
      report "tb_A14 RESULT: FAIL (" & integer'image(err_count) & " errors)" severity failure;
    else
      report "tb_A14 RESULT: PASS" severity note;
    end if;
    finish;
  end process;

end;
