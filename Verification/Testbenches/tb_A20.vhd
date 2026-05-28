use work.common.all;

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use std.env.all;

entity tb_a20 is
end entity tb_a20;

architecture bench of tb_a20 is

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

  constant A_WIDTH         : natural := CO_AQ_WIDTH_STD;
  constant N_WIDTH         : natural := CO_NQ_WIDTH_STD;

  signal iRI               : std_logic;
  signal iAq               : unsigned(A_WIDTH - 1 downto 0);
  signal iNq               : unsigned(N_WIDTH - 1 downto 0);
  signal oTemp             : unsigned(A_WIDTH - 1 downto 0);

  procedure check_case (
    ri          : std_logic;
    aq,
    nq          : integer;
    temp_actual : unsigned
  ) is

    variable exp : integer;

  begin

    if (ri = '0') then
      exp := aq;
    else
      exp := aq + (nq / 2);
    end if;

    check(temp_actual = to_unsigned(exp, temp_actual'length),
          "A20 TEMP mismatch exp=" & integer'image(exp) &
          " got=" & integer'image(to_integer(temp_actual))
        );

  end procedure check_case;

begin

  dut : entity work.a20_compute_temp(behavioral)

    generic map (
      A_WIDTH => A_WIDTH,
      N_WIDTH => N_WIDTH
    )
    port map (
      iRItype => iRI,
      iAq     => iAq,
      iNq     => iNq,
      oTemp   => oTemp
    );

  stim : process is
  begin

    -- Initial values (no defaults — set explicitly here)
    iRI <= '0';
    iAq <= (others => '0');
    iNq <= (others => '0');

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

    if (errCount > 0) then
      report "tb_A20 RESULT: FAIL (" & integer'image(errCount) & " errors)"
        severity failure;
    else
      report "tb_A20 RESULT: PASS"
        severity note;
    end if;

    finish;

  end process stim;

end architecture bench;
