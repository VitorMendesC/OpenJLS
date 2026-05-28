use work.common.all;

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use std.env.all;

entity tb_a14 is
end entity tb_a14;

architecture bench of tb_a14 is

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
  constant RUN_CNT_WIDTH   : natural := 8;

  signal iRa               : unsigned(BITNESS - 1 downto 0);
  signal iIx               : unsigned(BITNESS - 1 downto 0);
  signal iRunCnt           : unsigned(RUN_CNT_WIDTH - 1 downto 0);
  signal iEol              : std_logic;
  signal oRunCnt           : unsigned(RUN_CNT_WIDTH - 1 downto 0);
  signal oRunHit           : std_logic;
  signal oCont             : std_logic;

  procedure check_case (
    ra,
    ix,
    rc        : integer;
    eol       : std_logic;
    run_cnt_o : unsigned;
    run_hit_o : std_logic;
    cont_o    : std_logic
  ) is

    variable expHit  : std_logic;
    variable expCnt  : integer;
    variable expCont : std_logic;

  begin

    -- Lossless: hit iff Ix == Ra.
    if (ix = ra) then
      expHit := '1';
      expCnt := rc + 1;
    else
      expHit := '0';
      expCnt := rc;
    end if;

    if (expHit = '1' and eol = '0') then
      expCont := '1';
    else
      expCont := '0';
    end if;

    check(run_hit_o = expHit,
          "A14 RunHit mismatch: Ra=" & integer'image(ra) &
          " Ix=" & integer'image(ix) &
          " exp=" & std_logic'image(expHit) &
          " got=" & std_logic'image(run_hit_o)
        );
    check(run_cnt_o = to_unsigned(expCnt, run_cnt_o'length),
          "A14 RunCnt mismatch: exp=" & integer'image(expCnt) &
          " got=" & integer'image(to_integer(run_cnt_o))
        );
    check(cont_o = expCont,
          "A14 RunContinue mismatch: exp=" & std_logic'image(expCont) &
          " got=" & std_logic'image(cont_o)
        );

  end procedure check_case;

begin

  dut : entity work.a14_run_length_determination(behavioral)

    generic map (
      BITNESS       => BITNESS,
      RUN_CNT_WIDTH => RUN_CNT_WIDTH
    )
    port map (
      iRa           => iRa,
      iIx           => iIx,
      iRunCnt       => iRunCnt,
      iEol          => iEol,
      oRunCnt       => oRunCnt,
      oRunHit       => oRunHit,
      oRunContinue  => oCont
    );

  stim : process is
  begin

    -- Initial values (no defaults — set explicitly here)
    iRa     <= (others => '0');
    iIx     <= (others => '0');
    iRunCnt <= (others => '0');
    iEol    <= '0';

    -- Match, not EOL → hit + continue
    iRa     <= to_unsigned(10, iRa'length);
    iIx     <= to_unsigned(10, iIx'length);
    iRunCnt <= to_unsigned(0, iRunCnt'length);
    iEol    <= '0';
    wait for 1 ns;
    check_case(10, 10, 0, '0', oRunCnt, oRunHit, oCont);

    -- Ix = Ra + 1 (lossy would hit, lossless must miss)
    iRa     <= to_unsigned(10, iRa'length);
    iIx     <= to_unsigned(11, iIx'length);
    iRunCnt <= to_unsigned(5, iRunCnt'length);
    iEol    <= '0';
    wait for 1 ns;
    check_case(10, 11, 5, '0', oRunCnt, oRunHit, oCont);

    -- Ix = Ra + 2 → miss
    iRa     <= to_unsigned(10, iRa'length);
    iIx     <= to_unsigned(12, iIx'length);
    iRunCnt <= to_unsigned(5, iRunCnt'length);
    iEol    <= '0';
    wait for 1 ns;
    check_case(10, 12, 5, '0', oRunCnt, oRunHit, oCont);

    -- Match + EOL → hit but continue must drop
    iRa     <= to_unsigned(10, iRa'length);
    iIx     <= to_unsigned(10, iIx'length);
    iRunCnt <= to_unsigned(3, iRunCnt'length);
    iEol    <= '1';
    wait for 1 ns;
    check_case(10, 10, 3, '1', oRunCnt, oRunHit, oCont);

    -- Ix < Ra → miss
    iRa     <= to_unsigned(100, iRa'length);
    iIx     <= to_unsigned(98, iIx'length);
    iRunCnt <= to_unsigned(7, iRunCnt'length);
    iEol    <= '0';
    wait for 1 ns;
    check_case(100, 98, 7, '0', oRunCnt, oRunHit, oCont);

    -- Ix > Ra with EOL → miss
    iRa     <= to_unsigned(100, iRa'length);
    iIx     <= to_unsigned(102, iIx'length);
    iRunCnt <= to_unsigned(7, iRunCnt'length);
    iEol    <= '1';
    wait for 1 ns;
    check_case(100, 102, 7, '1', oRunCnt, oRunHit, oCont);

    if (errCount > 0) then
      report "tb_A14 RESULT: FAIL (" & integer'image(errCount) & " errors)"
        severity failure;
    else
      report "tb_A14 RESULT: PASS"
        severity note;
    end if;

    finish;

  end process stim;

end architecture bench;
