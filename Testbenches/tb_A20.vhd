use work.Common.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.env.all;

entity tb_A20 is
end;

architecture bench of tb_A20 is
  shared variable err_count : natural := 0;

  procedure check(cond : boolean; msg : string) is
  begin
    if not cond then
      report msg severity error;
      err_count := err_count + 1;
    end if;
  end procedure;

  constant A_WIDTH : natural := CO_AQ_WIDTH_STD;
  constant N_WIDTH : natural := CO_NQ_WIDTH_STD;

  signal iRI : std_logic := '0';
  signal iA365 : unsigned(A_WIDTH - 1 downto 0) := (others => '0');
  signal iA366 : unsigned(A_WIDTH - 1 downto 0) := (others => '0');
  signal iN366 : unsigned(N_WIDTH - 1 downto 0) := (others => '0');
  signal oTemp : unsigned(A_WIDTH - 1 downto 0);

  procedure check_case(
    ri   : std_logic;
    a365, a366, n366 : integer;
    temp_actual : unsigned
  ) is
    variable exp : integer;
  begin
    if ri = '0' then
      exp := a365;
    else
      exp := a366 + (n366 / 2);
    end if;

    check(temp_actual = to_unsigned(exp, temp_actual'length),
      "A20 TEMP mismatch exp=" & integer'image(exp) &
      " got=" & integer'image(to_integer(temp_actual))
    );
  end procedure;

begin

  dut : entity work.A20_compute_temp
    generic map(
      A_WIDTH => A_WIDTH,
      N_WIDTH => N_WIDTH
    )
    port map(
      iRItype => iRI,
      iA365   => iA365,
      iA366   => iA366,
      iN366   => iN366,
      oTemp   => oTemp
    );

  stim : process
  begin
    iRI   <= '0';
    iA365 <= to_unsigned(100, iA365'length);
    iA366 <= to_unsigned(200, iA366'length);
    iN366 <= to_unsigned(10, iN366'length);
    wait for 1 ns;
    check_case('0', 100, 200, 10, oTemp);

    iRI   <= '1';
    iA365 <= to_unsigned(100, iA365'length);
    iA366 <= to_unsigned(200, iA366'length);
    iN366 <= to_unsigned(10, iN366'length);
    wait for 1 ns;
    check_case('1', 100, 200, 10, oTemp);

    iRI   <= '1';
    iA365 <= to_unsigned(50, iA365'length);
    iA366 <= to_unsigned(300, iA366'length);
    iN366 <= to_unsigned(63, iN366'length);
    wait for 1 ns;
    check_case('1', 50, 300, 63, oTemp);

    if err_count > 0 then
      report "tb_A20 RESULT: FAIL (" & integer'image(err_count) & " errors)" severity failure;
    else
      report "tb_A20 RESULT: PASS" severity note;
    end if;
    finish;
  end process;

end;
