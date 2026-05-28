use work.common.all;

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use std.env.all;

entity tb_a18 is
end entity tb_a18;

architecture bench of tb_a18 is

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

  signal iRItype           : std_logic;
  signal iRa               : unsigned(BITNESS - 1 downto 0);
  signal iRb               : unsigned(BITNESS - 1 downto 0);
  signal iIx               : unsigned(BITNESS - 1 downto 0);
  signal oErr              : signed(BITNESS downto 0);

  procedure check_case (
    ri         : std_logic;
    ra,
    rb,
    ix         : integer;
    err_actual : signed
  ) is

    variable expPx  : integer;
    variable expErr : integer;

  begin

    if (ri = '1') then
      expPx := ra;
    else
      expPx := rb;
    end if;

    expErr := ix - expPx;

    check(err_actual = to_signed(expErr, err_actual'length),
          "A18 Err mismatch: exp=" & integer'image(expErr) &
          " got=" & integer'image(to_integer(err_actual))
        );

  end procedure check_case;

begin

  dut : entity work.a18_run_interruption_prediction_error(behavioral)

    generic map (
      BITNESS => BITNESS
    )
    port map (
      iRItype => iRItype,
      iRa     => iRa,
      iRb     => iRb,
      iIx     => iIx,
      oErrval => oErr
    );

  stim : process is
  begin

    -- Initial values (no defaults — set explicitly here)
    iRItype <= '0';
    iRa     <= (others => '0');
    iRb     <= (others => '0');
    iIx     <= (others => '0');

    iRItype <= '1';
    iRa     <= to_unsigned(10, iRa'length);
    iRb     <= to_unsigned(20, iRb'length);
    iIx     <= to_unsigned(15, iIx'length);
    wait for 1 ns;
    check_case('1', 10, 20, 15, oErr);

    iRItype <= '0';
    iRa     <= to_unsigned(10, iRa'length);
    iRb     <= to_unsigned(20, iRb'length);
    iIx     <= to_unsigned(15, iIx'length);
    wait for 1 ns;
    check_case('0', 10, 20, 15, oErr);

    iRItype <= '1';
    iRa     <= to_unsigned(100, iRa'length);
    iRb     <= to_unsigned(0, iRb'length);
    iIx     <= to_unsigned(80, iIx'length);
    wait for 1 ns;
    check_case('1', 100, 0, 80, oErr);

    iRItype <= '0';
    iRa     <= to_unsigned(100, iRa'length);
    iRb     <= to_unsigned(0, iRb'length);
    iIx     <= to_unsigned(80, iIx'length);
    wait for 1 ns;
    check_case('0', 100, 0, 80, oErr);

    if (errCount > 0) then
      report "tb_A18 RESULT: FAIL (" & integer'image(errCount) & " errors)"
        severity failure;
    else
      report "tb_A18 RESULT: PASS"
        severity note;
    end if;

    finish;

  end process stim;

end architecture bench;
