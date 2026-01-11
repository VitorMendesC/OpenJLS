
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.Common.all;

entity mode_selection_tb is
end;

architecture bench of mode_selection_tb is
  -- Clock period
  constant clk_period : time := 5 ns;
  -- Generics
  constant BITNESS : natural range 8 to 16 := 12;
  -- Ports
  signal iCLk         : std_logic                          := '1';
  signal iStrb        : std_logic                          := '0';
  signal iD1          : std_logic_vector(BITNESS downto 0) := ui2std(0, BITNESS + 1); -- signed
  signal iD2          : std_logic_vector(BITNESS downto 0) := ui2std(1, BITNESS + 1); -- signed
  signal iD3          : std_logic_vector(BITNESS downto 0) := ui2std(2, BITNESS + 1); -- signed
  signal oModeRegular : std_logic;
  signal oModeRun     : std_logic;
  signal oStrb        : std_logic;
begin

  mode_selection_inst : entity work.mode_selection
    generic map(
      BITNESS => BITNESS
    )
    port map
    (
      iCLk         => iCLk,
      iStrb        => iStrb,
      iD1          => iD1,
      iD2          => iD2,
      iD3          => iD3,
      oModeRegular => oModeRegular,
      oModeRun     => oModeRun,
      oStrb        => oStrb
    );

  iClk <= not iClk after clk_period/2;
  process
  begin

    wait for 50 * clk_period;
    iStrb <= '1';
    wait for clk_period;
    iStrb <= '0';

    wait for 50 * clk_period;
    iD1 <= ui2std(0, BITNESS + 1);
    iD2 <= ui2std(0, BITNESS + 1);
    iD3 <= ui2std(0, BITNESS + 1);
    wait for clk_period;
    iStrb <= '1';
    wait for clk_period;
    iStrb <= '0';

    wait;

  end process;
end;