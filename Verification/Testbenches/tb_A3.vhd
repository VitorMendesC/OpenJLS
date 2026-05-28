
library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use std.env.all;

entity tb_a3 is
end entity tb_a3;

architecture bench of tb_a3 is

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

  -- Clock period
  constant CSTDWAIT        : time := 100 ns;
  -- Generics
  constant BITNESS         : natural range 8 to 16 := 12;
  -- Ports
  signal iD1               : signed(BITNESS downto 0);
  signal iD2               : signed(BITNESS downto 0);
  signal iD3               : signed(BITNESS downto 0);
  signal oModeRun          : std_logic;

begin

  a3_mode_selection_inst : entity work.a3_mode_selection(behavioral)

    generic map (
      BITNESS  => BITNESS
    )
    port map (
      iD1      => iD1,
      iD2      => iD2,
      iD3      => iD3,
      oModeRun => oModeRun
    );

  stim : process is
  begin

    -- Initial values (no defaults — set explicitly here)
    iD1 <= (others => '1');
    iD2 <= (others => '0');
    iD3 <= (others => '0');

    wait for CSTDWAIT;

    -- All-zero gradients test
    wait for CSTDWAIT;
    iD1 <= to_signed(0, BITNESS + 1);
    iD2 <= to_signed(0, BITNESS + 1);
    iD3 <= to_signed(0, BITNESS + 1);

    wait for CSTDWAIT;
    check(oModeRun = '1', "Test 1 Failed: oModeRun should be asserted for zero gradients");

    -- Non-zero gradients test
    wait for CSTDWAIT;
    iD1 <= (others => '1');
    iD2 <= (others => '1');
    iD3 <= (others => '1');

    wait for CSTDWAIT;
    check(oModeRun = '0', "Test 2 Failed: oModeRun should be deasserted for non-zero gradients");

    if (errCount > 0) then
      report "tb_A3 RESULT: FAIL (" & integer'image(errCount) & " errors)"
        severity failure;
    else
      report "tb_A3 RESULT: PASS"
        severity note;
    end if;

    finish;

  end process stim;

end architecture bench;
