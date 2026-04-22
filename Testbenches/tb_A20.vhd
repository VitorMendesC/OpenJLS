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

  signal iRI   : std_logic := '0';
  signal iAq   : unsigned(A_WIDTH - 1 downto 0) := (others => '0');
  signal iNq   : unsigned(N_WIDTH - 1 downto 0) := (others => '0');
  signal oTemp : unsigned(A_WIDTH - 1 downto 0);

  procedure check_case(
    ri          : std_logic;
    aq, nq      : integer;
    temp_actual : unsigned
  ) is
    variable exp : integer;
  begin
    if ri = '0' then
      exp := aq;
    else
      exp := aq + (nq / 2);
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
      iAq     => iAq,
      iNq     => iNq,
      oTemp   => oTemp
    );

  stim : process
  begin
    -- RItype = 0 → TEMP = Aq (Nq ignored)
    iRI <= '0';
    iAq <= to_unsigned(100, iAq'length);
    iNq <= to_unsigned(10, iNq'length);
    wait for 1 ns;
    check_case('0', 100, 10, oTemp);

    -- RItype = 0, Nq varied — should not affect output
    iRI <= '0';
    iAq <= to_unsigned(100, iAq'length);
    iNq <= to_unsigned(63, iNq'length);
    wait for 1 ns;
    check_case('0', 100, 63, oTemp);

    -- RItype = 1 → TEMP = Aq + (Nq >> 1)
    iRI <= '1';
    iAq <= to_unsigned(200, iAq'length);
    iNq <= to_unsigned(10, iNq'length);
    wait for 1 ns;
    check_case('1', 200, 10, oTemp);

    iRI <= '1';
    iAq <= to_unsigned(300, iAq'length);
    iNq <= to_unsigned(63, iNq'length);
    wait for 1 ns;
    check_case('1', 300, 63, oTemp);

    -- Edge: Nq = 0
    iRI <= '1';
    iAq <= to_unsigned(42, iAq'length);
    iNq <= to_unsigned(0, iNq'length);
    wait for 1 ns;
    check_case('1', 42, 0, oTemp);

    -- Edge: Nq = 1 (>>1 = 0)
    iRI <= '1';
    iAq <= to_unsigned(42, iAq'length);
    iNq <= to_unsigned(1, iNq'length);
    wait for 1 ns;
    check_case('1', 42, 1, oTemp);

    if err_count > 0 then
      report "tb_A20 RESULT: FAIL (" & integer'image(err_count) & " errors)" severity failure;
    else
      report "tb_A20 RESULT: PASS" severity note;
    end if;
    finish;
  end process;

end;
