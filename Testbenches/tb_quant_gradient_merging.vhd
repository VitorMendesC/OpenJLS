
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity quant_gradient_merging_tb is
end;

architecture bench of quant_gradient_merging_tb is
  -- Clock period
  constant clk_period : time := 5 ns;
  -- Generics
  -- Ports
  signal iClk  : std_logic := '1';
  signal iStrb : std_logic := '0';
  signal iQ1   : signed(3 downto 0);
  signal iQ2   : signed(3 downto 0);
  signal iQ3   : signed(3 downto 0);
  signal oQ1   : signed(3 downto 0);
  signal oQ2   : signed(3 downto 0);
  signal oQ3   : signed(3 downto 0);
  signal oStrb : std_logic;
  signal oSign : std_logic;

begin

  quant_gradient_merging_inst : entity work.quant_gradient_merging
    port map
    (
      iClk  => iClk,
      iStrb => iStrb,
      iQ1   => iQ1,
      iQ2   => iQ2,
      iQ3   => iQ3,
      oQ1   => oQ1,
      oQ2   => oQ2,
      oQ3   => oQ3,
      oStrb => oStrb,
      oSign => oSign
    );

  iClk <= not iClk after clk_period/2;

  process
  begin

    wait for 10 * clk_period;
    iQ1   <= to_signed(1, 4);
    iQ2   <= to_signed(1, 4);
    iQ3   <= to_signed(1, 4);
    iStrb <= '1';
    wait for clk_period;
    iStrb <= '0';

    wait for 10 * clk_period;
    iQ1   <= to_signed(-1, 4);
    iQ2   <= to_signed(2, 4);
    iQ3   <= to_signed(2, 4);
    iStrb <= '1';
    wait for clk_period;
    iStrb <= '0';

    wait for 10 * clk_period;
    iQ1   <= to_signed(0, 4);
    iQ2   <= to_signed(-1, 4);
    iQ3   <= to_signed(2, 4);
    iStrb <= '1';
    wait for clk_period;
    iStrb <= '0';

    wait for 10 * clk_period;
    iQ1   <= to_signed(1, 4);
    iQ2   <= to_signed(-2, 4);
    iQ3   <= to_signed(3, 4);
    iStrb <= '1';
    wait for clk_period;
    iStrb <= '0';

    wait for 10 * clk_period;
    iQ1   <= to_signed(0, 4);
    iQ2   <= to_signed(0, 4);
    iQ3   <= to_signed(-3, 4);
    iStrb <= '1';
    wait for clk_period;
    iStrb <= '0';

    wait;
  end process;

end;