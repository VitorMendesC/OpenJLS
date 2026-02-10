use work.Common.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.env.all;

entity tb_A16 is
end;

architecture bench of tb_A16 is
  shared variable err_count : natural := 0;

  procedure check(cond : boolean; msg : string) is
  begin
    if not cond then
      report msg severity error;
      err_count := err_count + 1;
    end if;
  end procedure;

  constant BITNESS         : natural := CO_BITNESS_STD;
  constant RUN_CNT_WIDTH   : natural := 16;
  constant RUN_INDEX_WIDTH : natural := 5;
  constant J_WIDTH         : natural := 5;
  constant NEAR_VAL        : natural := 1;

  signal iIx        : unsigned(BITNESS - 1 downto 0) := (others => '0');
  signal iRunVal    : unsigned(BITNESS - 1 downto 0) := (others => '0');
  signal iRunCnt    : unsigned(RUN_CNT_WIDTH - 1 downto 0) := (others => '0');
  signal iRunIndex  : unsigned(RUN_INDEX_WIDTH - 1 downto 0) := (others => '0');
  signal oRunIndex  : unsigned(RUN_INDEX_WIDTH - 1 downto 0);
  signal oAppendVal : std_logic;
  signal oPrefixBit : std_logic;
  signal oRunCntVal : unsigned(RUN_CNT_WIDTH - 1 downto 0);
  signal oRunCntLen : unsigned(J_WIDTH - 1 downto 0);

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
    ix, runval, run_cnt, run_idx : integer;
    out_idx   : unsigned;
    append_o  : std_logic;
    prefix_o  : std_logic;
    cnt_val_o : unsigned;
    cnt_len_o : unsigned
  ) is
    variable diff      : integer;
    variable vJ        : natural;
    variable exp_idx   : integer;
    variable exp_val   : std_logic;
    variable exp_bit   : std_logic;
    variable exp_len   : integer;
    variable exp_rc    : integer;
  begin
    diff := abs(ix - runval);
    vJ   := C_J_TABLE(run_idx);

    exp_idx := run_idx;
    exp_val := '0';
    exp_bit := '0';
    exp_len := 0;
    exp_rc  := 0;

    if diff > integer(NEAR_VAL) then
      exp_val := '1';
      exp_bit := '0';
      exp_len := vJ;
      exp_rc  := run_cnt;
      if run_idx > 0 then
        exp_idx := run_idx - 1;
      end if;
    elsif run_cnt > 0 then
      exp_val := '1';
      exp_bit := '1';
      exp_len := 0;
      exp_rc  := 0;
    end if;

    check(append_o = exp_val,
      "A16 append valid mismatch: Ix=" & integer'image(ix) &
      " RunVal=" & integer'image(runval)
    );
    check(prefix_o = exp_bit,
      "A16 prefix bit mismatch: Ix=" & integer'image(ix) &
      " RunVal=" & integer'image(runval)
    );
    check(cnt_len_o = to_unsigned(exp_len, cnt_len_o'length),
      "A16 run count length mismatch: exp=" & integer'image(exp_len) &
      " got=" & integer'image(to_integer(cnt_len_o))
    );
    check(cnt_val_o = to_unsigned(exp_rc, cnt_val_o'length),
      "A16 run count value mismatch: exp=" & integer'image(exp_rc) &
      " got=" & integer'image(to_integer(cnt_val_o))
    );
    check(out_idx = to_unsigned(exp_idx, out_idx'length),
      "A16 run index mismatch: exp=" & integer'image(exp_idx) &
      " got=" & integer'image(to_integer(out_idx))
    );
  end procedure;

begin

  dut : entity work.A16_encode_run_segments_short
    generic map(
      BITNESS         => BITNESS,
      RUN_CNT_WIDTH   => RUN_CNT_WIDTH,
      RUN_INDEX_WIDTH => RUN_INDEX_WIDTH,
      J_WIDTH         => J_WIDTH,
      NEAR            => NEAR_VAL
    )
    port map(
      iIx          => iIx,
      iRunVal      => iRunVal,
      iRunCnt      => iRunCnt,
      iRunIndex    => iRunIndex,
      oRunIndex    => oRunIndex,
      oAppendValid => oAppendVal,
      oPrefixBit   => oPrefixBit,
      oRunCntVal   => oRunCntVal,
      oRunCntLen   => oRunCntLen
    );

  stim : process
  begin
    iIx       <= to_unsigned(10, iIx'length);
    iRunVal   <= to_unsigned(10, iRunVal'length);
    iRunCnt   <= to_unsigned(5, iRunCnt'length);
    iRunIndex <= to_unsigned(4, iRunIndex'length);
    wait for 1 ns;
    check_case(10, 10, 5, 4, oRunIndex, oAppendVal, oPrefixBit, oRunCntVal, oRunCntLen);

    iIx       <= to_unsigned(10, iIx'length);
    iRunVal   <= to_unsigned(12, iRunVal'length);
    iRunCnt   <= to_unsigned(3, iRunCnt'length);
    iRunIndex <= to_unsigned(4, iRunIndex'length);
    wait for 1 ns;
    check_case(10, 12, 3, 4, oRunIndex, oAppendVal, oPrefixBit, oRunCntVal, oRunCntLen);

    iIx       <= to_unsigned(10, iIx'length);
    iRunVal   <= to_unsigned(12, iRunVal'length);
    iRunCnt   <= to_unsigned(3, iRunCnt'length);
    iRunIndex <= to_unsigned(0, iRunIndex'length);
    wait for 1 ns;
    check_case(10, 12, 3, 0, oRunIndex, oAppendVal, oPrefixBit, oRunCntVal, oRunCntLen);

    iIx       <= to_unsigned(10, iIx'length);
    iRunVal   <= to_unsigned(11, iRunVal'length);
    iRunCnt   <= to_unsigned(0, iRunCnt'length);
    iRunIndex <= to_unsigned(6, iRunIndex'length);
    wait for 1 ns;
    check_case(10, 11, 0, 6, oRunIndex, oAppendVal, oPrefixBit, oRunCntVal, oRunCntLen);

    if err_count > 0 then
      report "tb_A16 RESULT: FAIL (" & integer'image(err_count) & " errors)" severity failure;
    else
      report "tb_A16 RESULT: PASS" severity note;
    end if;
    finish;
  end process;

end;
