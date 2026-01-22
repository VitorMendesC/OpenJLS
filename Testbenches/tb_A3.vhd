
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_A3 is
end;

architecture bench of tb_A3 is
  -- Clock period
  constant cStdWait : time := 100 ns;
  -- Generics
  constant BITNESS : natural range 8 to 16 := 12;
  -- Ports
  signal iD1          : signed(BITNESS downto 0) := (others => '1');
  signal iD2          : signed(BITNESS downto 0) := (others => '0');
  signal iD3          : signed(BITNESS downto 0) := (others => '0');
  signal oModeRegular : std_logic;
  signal oModeRun     : std_logic;
begin

  A3_mode_selection_inst : entity work.A3_mode_selection
    generic map(
      BITNESS => BITNESS
    )
    port map
    (
      iD1          => iD1,
      iD2          => iD2,
      iD3          => iD3,
      oModeRegular => oModeRegular,
      oModeRun     => oModeRun
    );

  process
  begin

    wait for cStdWait;

    -- All-zero gradients test
    wait for cStdWait;
    iD1 <= to_signed(0, BITNESS + 1);
    iD2 <= to_signed(0, BITNESS + 1);
    iD3 <= to_signed(0, BITNESS + 1);

    wait for cStdWait;
    assert oModeRun = '1'
    report "Test 1 Failed: oModeRun should be asserted for zero gradients"
      severity failure;

    assert oModeRegular = '0'
    report "Test 1 Failed: oModeRegular should be deasserted for zero gradients"
      severity failure;

    -- Non-zero gradients test
    wait for cStdWait;
    iD1 <= (others => '1');
    iD2 <= (others => '1');
    iD3 <= (others => '1');

    wait for cStdWait;
    assert oModeRun = '0'
    report "Test 2 Failed: oModeRun should be deasserted for non-zero gradients"
      severity failure;

    assert oModeRegular = '1'
    report "Test 2 Failed: oModeRegular should be asserted for non-zero gradients"
      severity failure;

    report "All tests passed!" severity note;
    wait;
  end process;

end;
