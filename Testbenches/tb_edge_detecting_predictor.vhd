
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity edge_detecting_predictor_tb is
end;

architecture bench of edge_detecting_predictor_tb is
  -- Clock period
  constant clk_period : time := 5 ns;
  -- Generics
  constant BITNESS : natural range 8 to 16 := 12;
  -- Ports
  signal iClk  : std_logic := '1';
  signal iStrb : std_logic := '0';
  signal iA    : unsigned (BITNESS - 1 downto 0);
  signal iB    : unsigned (BITNESS - 1 downto 0);
  signal iC    : unsigned (BITNESS - 1 downto 0);
  signal oStrb : std_logic;
  signal oPx   : unsigned (BITNESS - 1 downto 0);
begin

  edge_detecting_predictor_inst : entity work.edge_detecting_predictor
    generic map(
      BITNESS => BITNESS
    )
    port map
    (
      iClk  => iClk,
      iStrb => iStrb,
      iA    => iA,
      iB    => iB,
      iC    => iC,
      oStrb => oStrb,
      oPx   => oPx
    );

  iClk <= not iClk after clk_period/2;

  process
  begin

    wait for 10 * clk_period;
    iA    <= to_unsigned(330, BITNESS);
    iB    <= to_unsigned(440, BITNESS);
    iC    <= to_unsigned(550, BITNESS);
    iStrb <= '1';
    wait for clk_period;
    iStrb <= '0';

    wait for 10 * clk_period;
    iA    <= to_unsigned(3000, BITNESS);
    iB    <= to_unsigned(2000, BITNESS);
    iC    <= to_unsigned(100, BITNESS);
    iStrb <= '1';
    wait for clk_period;
    iStrb <= '0';

    wait for 10 * clk_period;
    iA    <= to_unsigned(3000, BITNESS);
    iB    <= to_unsigned(200, BITNESS);
    iC    <= to_unsigned(1000, BITNESS);
    iStrb <= '1';
    wait for clk_period;
    iStrb <= '0';

    wait;

  end process;

end;