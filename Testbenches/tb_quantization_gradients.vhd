
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity quantization_gradients_tb is
end;

architecture bench of quantization_gradients_tb is
  -- Clock period
  constant clk_period : time := 5 ns;
  -- Generics
  constant BITNESS : natural range 8 to 16 := 12;
  -- Ports
  signal iClk  : std_logic                 := '1';
  signal iStrb : std_logic                 := '0';
  signal iD1   : signed (BITNESS downto 0) := TO_SIGNED(220, BITNESS + 1);
  signal iD2   : signed (BITNESS downto 0) := TO_SIGNED(60, BITNESS + 1);
  signal iD3   : signed (BITNESS downto 0) := TO_SIGNED(12, BITNESS + 1);
  signal oQ1   : signed (3 downto 0);
  signal oQ2   : signed (3 downto 0);
  signal oQ3   : signed (3 downto 0);
  signal oStrb : std_logic;
begin

  quantization_gradients_inst : entity work.quantization_gradients
    generic map(
      BITNESS => BITNESS
    )
    port map
    (
      iClk  => iClk,
      iStrb => iStrb,
      iD1   => iD1,
      iD2   => iD2,
      iD3   => iD3,
      oQ1   => oQ1,
      oQ2   => oQ2,
      oQ3   => oQ3,
      oStrb => oStrb
    );

  iClk <= not iClk after clk_period/2;

  process
  begin
    wait for 10 * clk_period;
    iStrb <= '1';
    wait for clk_period;
    iStrb <= '0';

    wait for 50 * clk_period;
    iD1   <= TO_SIGNED(-220, BITNESS + 1);
    iD2   <= TO_SIGNED(-60, BITNESS + 1);
    iD3   <= TO_SIGNED(-12, BITNESS + 1);
    iStrb <= '1';
    wait for clk_period;
    iStrb <= '0';

    wait;

  end process;

end;