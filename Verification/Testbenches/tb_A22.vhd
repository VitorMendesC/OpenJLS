use work.common.all;

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use std.env.all;

entity tb_a22 is
end entity tb_a22;

architecture bench of tb_a22 is

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

  constant ERROR_WIDTH     : natural := CO_ERROR_VALUE_WIDTH_STD;
  constant ME_WIDTH        : natural := CO_MAPPED_ERROR_VAL_WIDTH_STD;

  signal iErr              : signed(ERROR_WIDTH - 1 downto 0);
  signal iRI               : std_logic;
  signal iMap              : std_logic;
  signal oEmErr            : unsigned(ME_WIDTH - 1 downto 0);

  procedure check_case (
    errv      : integer;
    ri,
    map_flag  : std_logic;
    em_actual : unsigned
  ) is

    variable exp  : integer;
    variable riI  : integer;
    variable mapI : integer;

  begin

    if (ri = '1') then
      riI := 1;
    else
      riI := 0;
    end if;

    if (map_flag = '1') then
      mapI := 1;
    else
      mapI := 0;
    end if;

    exp := 2 * abs(errv) - riI - mapI;

    check(em_actual = to_unsigned(exp, em_actual'length),
          "A22 mismatch: Err=" & integer'image(errv) &
          " RI=" & std_logic'image(ri) &
          " map=" & std_logic'image(map_flag) &
          " exp=" & integer'image(exp) &
          " got=" & integer'image(to_integer(em_actual))
        );

  end procedure check_case;

begin

  dut : entity work.a22_errval_mapping(behavioral)

    generic map (
      ERROR_WIDTH         => ERROR_WIDTH,
      MAPPED_ERRVAL_WIDTH => ME_WIDTH
    )
    port map (
      iErrval             => iErr,
      iRItype             => iRI,
      iMap                => iMap,
      oEmErrVal           => oEmErr
    );

  stim : process is
  begin

    -- Initial values (no defaults — set explicitly here)
    iErr <= (others => '0');
    iRI  <= '0';
    iMap <= '0';

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

    if (errCount > 0) then
      report "tb_A22 RESULT: FAIL (" & integer'image(errCount) & " errors)"
        severity failure;
    else
      report "tb_A22 RESULT: PASS"
        severity note;
    end if;

    finish;

  end process stim;

end architecture bench;
