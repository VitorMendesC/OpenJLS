use work.Common.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.env.all;

entity tb_A18 is
end;

architecture bench of tb_A18 is
  shared variable err_count : natural := 0;

  procedure check(cond : boolean; msg : string) is
  begin
    if not cond then
      report msg severity error;
      err_count := err_count + 1;
    end if;
  end procedure;

  constant BITNESS : natural := CO_BITNESS_STD;

  signal iRItype : std_logic := '0';
  signal iRa     : unsigned(BITNESS - 1 downto 0) := (others => '0');
  signal iRb     : unsigned(BITNESS - 1 downto 0) := (others => '0');
  signal iIx     : unsigned(BITNESS - 1 downto 0) := (others => '0');
  signal oPx     : unsigned(BITNESS - 1 downto 0);
  signal oErr    : signed(BITNESS downto 0);

  procedure check_case(
    ri         : std_logic;
    ra, rb, ix : integer;
    px_actual  : unsigned;
    err_actual : signed
  ) is
    variable exp_px  : integer;
    variable exp_err : integer;
  begin
    if ri = '1' then
      exp_px := ra;
    else
      exp_px := rb;
    end if;
    exp_err := ix - exp_px;

    check(px_actual = to_unsigned(exp_px, px_actual'length),
      "A18 Px mismatch: exp=" & integer'image(exp_px) &
      " got=" & integer'image(to_integer(px_actual))
    );
    check(err_actual = to_signed(exp_err, err_actual'length),
      "A18 Err mismatch: exp=" & integer'image(exp_err) &
      " got=" & integer'image(to_integer(err_actual))
    );
  end procedure;

begin

  dut : entity work.A18_run_interruption_prediction_error
    generic map(
      BITNESS => BITNESS
    )
    port map(
      iRItype => iRItype,
      iRa     => iRa,
      iRb     => iRb,
      iIx     => iIx,
      oPx     => oPx,
      oErrval => oErr
    );

  stim : process
  begin
    iRItype <= '1';
    iRa     <= to_unsigned(10, iRa'length);
    iRb     <= to_unsigned(20, iRb'length);
    iIx     <= to_unsigned(15, iIx'length);
    wait for 1 ns;
    check_case('1', 10, 20, 15, oPx, oErr);

    iRItype <= '0';
    iRa     <= to_unsigned(10, iRa'length);
    iRb     <= to_unsigned(20, iRb'length);
    iIx     <= to_unsigned(15, iIx'length);
    wait for 1 ns;
    check_case('0', 10, 20, 15, oPx, oErr);

    iRItype <= '1';
    iRa     <= to_unsigned(100, iRa'length);
    iRb     <= to_unsigned(0, iRb'length);
    iIx     <= to_unsigned(80, iIx'length);
    wait for 1 ns;
    check_case('1', 100, 0, 80, oPx, oErr);

    iRItype <= '0';
    iRa     <= to_unsigned(100, iRa'length);
    iRb     <= to_unsigned(0, iRb'length);
    iIx     <= to_unsigned(80, iIx'length);
    wait for 1 ns;
    check_case('0', 100, 0, 80, oPx, oErr);

    if err_count > 0 then
      report "tb_A18 RESULT: FAIL (" & integer'image(err_count) & " errors)" severity failure;
    else
      report "tb_A18 RESULT: PASS" severity note;
    end if;
    finish;
  end process;

end;
