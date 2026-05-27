
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.env.all;

entity tb_A15 is
end;

architecture bench of tb_A15 is
  shared variable err_count : natural := 0;

  procedure check(cond : boolean; msg : string) is
  begin
    if not cond then
      report msg severity error;
      err_count := err_count + 1;
    end if;
  end procedure;

  constant RUN_CNT_WIDTH   : natural := 16;
  constant RUN_INDEX_WIDTH : natural := 5;

  signal iRunCnt      : unsigned(RUN_CNT_WIDTH - 1 downto 0) := (others => '0');
  signal iRunIndex    : unsigned(RUN_INDEX_WIDTH - 1 downto 0) := (others => '0');
  signal oRunCnt      : unsigned(RUN_CNT_WIDTH - 1 downto 0);
  signal oRunIndex    : unsigned(RUN_INDEX_WIDTH - 1 downto 0);
  signal oAppendValid : std_logic;
  signal oAppendCount : unsigned(RUN_CNT_WIDTH - 1 downto 0);

  type t_j_table is array (0 to 31) of natural;
  constant C_J_TABLE : t_j_table := (
    0, 0, 0, 0,
    1, 1, 1, 1,
    2, 2, 2, 2,
    3, 3, 3, 3,
    4, 4,
    5, 5,
    6, 6,
    7, 7,
    8, 9, 10, 11, 12, 13, 14, 15
  );

  procedure check_case(
    run_cnt, run_idx : integer;
    out_cnt          : unsigned;
    out_idx          : unsigned;
    valid_o          : std_logic;
    append_cnt_o     : unsigned
  ) is
    variable vJ        : natural;
    variable vRg       : integer;
    variable exp_cnt   : integer;
    variable exp_idx   : integer;
    variable exp_valid : std_logic;
    variable exp_append : integer;
  begin
    exp_cnt    := run_cnt;
    exp_idx    := run_idx;
    exp_append := 0;

    for i in 0 to C_J_TABLE'length - 1 loop
      vJ  := C_J_TABLE(exp_idx);
      vRg := 2 ** vJ;
      if exp_cnt >= vRg then
        exp_cnt    := exp_cnt - vRg;
        exp_append := exp_append + 1;
        if exp_idx < 31 then
          exp_idx := exp_idx + 1;
        end if;
      else
        exit;
      end if;
    end loop;

    if exp_append > 0 then
      exp_valid := '1';
    else
      exp_valid := '0';
    end if;

    check(valid_o = exp_valid,
      "A15 append valid mismatch: RunCnt=" & integer'image(run_cnt) &
      " RunIndex=" & integer'image(run_idx)
    );
    check(append_cnt_o = to_unsigned(exp_append, append_cnt_o'length),
      "A15 append count mismatch: exp=" & integer'image(exp_append) &
      " got=" & integer'image(to_integer(append_cnt_o)) &
      " RunCnt=" & integer'image(run_cnt) &
      " RunIndex=" & integer'image(run_idx)
    );
    check(out_cnt = to_unsigned(exp_cnt, out_cnt'length),
      "A15 RunCnt mismatch: exp=" & integer'image(exp_cnt) &
      " got=" & integer'image(to_integer(out_cnt))
    );
    check(out_idx = to_unsigned(exp_idx, out_idx'length),
      "A15 RunIndex mismatch: exp=" & integer'image(exp_idx) &
      " got=" & integer'image(to_integer(out_idx))
    );
  end procedure;

begin

  dut : entity work.A15_encode_run_segments
    generic map(
      RUN_CNT_WIDTH   => RUN_CNT_WIDTH,
      RUN_INDEX_WIDTH => RUN_INDEX_WIDTH
    )
    port map(
      iRunCnt      => iRunCnt,
      iRunIndex    => iRunIndex,
      oRunCnt      => oRunCnt,
      oRunIndex    => oRunIndex,
      oAppendValid => oAppendValid,
      oAppendCount => oAppendCount
    );

  stim : process
  begin
    iRunCnt   <= to_unsigned(0, iRunCnt'length);
    iRunIndex <= to_unsigned(0, iRunIndex'length);
    wait for 1 ns;
    check_case(0, 0, oRunCnt, oRunIndex, oAppendValid, oAppendCount);

    iRunCnt   <= to_unsigned(1, iRunCnt'length);
    iRunIndex <= to_unsigned(0, iRunIndex'length);
    wait for 1 ns;
    check_case(1, 0, oRunCnt, oRunIndex, oAppendValid, oAppendCount);

    iRunCnt   <= to_unsigned(5, iRunCnt'length);
    iRunIndex <= to_unsigned(3, iRunIndex'length);
    wait for 1 ns;
    check_case(5, 3, oRunCnt, oRunIndex, oAppendValid, oAppendCount);

    iRunCnt   <= to_unsigned(40000, iRunCnt'length);
    iRunIndex <= to_unsigned(31, iRunIndex'length);
    wait for 1 ns;
    check_case(40000, 31, oRunCnt, oRunIndex, oAppendValid, oAppendCount);

    iRunCnt   <= to_unsigned(10, iRunCnt'length);
    iRunIndex <= to_unsigned(10, iRunIndex'length);
    wait for 1 ns;
    check_case(10, 10, oRunCnt, oRunIndex, oAppendValid, oAppendCount);

    iRunCnt   <= to_unsigned(2, iRunCnt'length);
    iRunIndex <= to_unsigned(4, iRunIndex'length);
    wait for 1 ns;
    check_case(2, 4, oRunCnt, oRunIndex, oAppendValid, oAppendCount);

    if err_count > 0 then
      report "tb_A15 RESULT: FAIL (" & integer'image(err_count) & " errors)" severity failure;
    else
      report "tb_A15 RESULT: PASS" severity note;
    end if;
    finish;
  end process;

end;
