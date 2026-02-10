use work.Common.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.env.all;

entity tb_A22 is
end;

architecture bench of tb_A22 is
  shared variable err_count : natural := 0;

  procedure check(cond : boolean; msg : string) is
  begin
    if not cond then
      report msg severity error;
      err_count := err_count + 1;
    end if;
  end procedure;

  constant ERR_WIDTH : natural := CO_ERROR_VALUE_WIDTH_STD;
  constant ME_WIDTH  : natural := CO_MAPPED_ERROR_VAL_WIDTH_STD;

  signal iErr    : signed(ERR_WIDTH - 1 downto 0) := (others => '0');
  signal iRI     : std_logic := '0';
  signal iMap    : std_logic := '0';
  signal oEmErr  : unsigned(ME_WIDTH - 1 downto 0);

  procedure check_case(
    errv    : integer;
    ri, map_flag : std_logic;
    em_actual : unsigned
  ) is
    variable exp : integer;
    variable ri_i : integer;
    variable map_i : integer;
  begin
    if ri = '1' then
      ri_i := 1;
    else
      ri_i := 0;
    end if;
    if map_flag = '1' then
      map_i := 1;
    else
      map_i := 0;
    end if;

    exp := 2 * abs(errv) - ri_i - map_i;

    check(em_actual = to_unsigned(exp, em_actual'length),
      "A22 mismatch: Err=" & integer'image(errv) &
      " RI=" & std_logic'image(ri) &
      " map=" & std_logic'image(map_flag) &
      " exp=" & integer'image(exp) &
      " got=" & integer'image(to_integer(em_actual))
    );
  end procedure;

begin

  dut : entity work.A22_errval_mapping
    generic map(
      ERR_WIDTH           => ERR_WIDTH,
      MAPPED_ERRVAL_WIDTH => ME_WIDTH
    )
    port map(
      iErrval   => iErr,
      iRItype   => iRI,
      iMap      => iMap,
      oEMErrval => oEmErr
    );

  stim : process
  begin
    iErr <= to_signed(5, iErr'length);
    iRI  <= '0';
    iMap <= '0';
    wait for 1 ns;
    check_case(5, '0', '0', oEmErr);

    iErr <= to_signed(-5, iErr'length);
    iRI  <= '0';
    iMap <= '0';
    wait for 1 ns;
    check_case(-5, '0', '0', oEmErr);

    iErr <= to_signed(5, iErr'length);
    iRI  <= '1';
    iMap <= '0';
    wait for 1 ns;
    check_case(5, '1', '0', oEmErr);

    iErr <= to_signed(5, iErr'length);
    iRI  <= '1';
    iMap <= '1';
    wait for 1 ns;
    check_case(5, '1', '1', oEmErr);

    iErr <= to_signed(-3, iErr'length);
    iRI  <= '0';
    iMap <= '1';
    wait for 1 ns;
    check_case(-3, '0', '1', oEmErr);

    if err_count > 0 then
      report "tb_A22 RESULT: FAIL (" & integer'image(err_count) & " errors)" severity failure;
    else
      report "tb_A22 RESULT: PASS" severity note;
    end if;
    finish;
  end process;

end;
