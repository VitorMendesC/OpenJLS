
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use Work.Common.all;

entity tb_gradient_comp is
end;

architecture bench of tb_gradient_comp is

  -- Clock period
  constant clk_period : time := 5 ns;
  -- Generics       
  constant BITNESS : natural range 8 to 16 := 12;
  -- Ports
  signal iCLk  : std_logic                      := '1';
  signal iStrb : std_logic                      := '0';
  signal iA    : unsigned(BITNESS - 1 downto 0) := to_unsigned(10, BITNESS);
  signal iB    : unsigned(BITNESS - 1 downto 0) := to_unsigned(8, BITNESS);
  signal iC    : unsigned(BITNESS - 1 downto 0) := to_unsigned(10, BITNESS);
  signal iD    : unsigned(BITNESS - 1 downto 0) := to_unsigned(7, BITNESS);
  signal oD1   : signed(BITNESS downto 0);
  signal oD2   : signed(BITNESS downto 0);
  signal oD3   : signed(BITNESS downto 0);
  signal oStrb : std_logic;

begin

  gradient_comp_inst : entity work.gradient_comp
    generic map(
      BITNESS => BITNESS
    )
    port map
    (
      iCLk  => iCLk,
      iStrb => iStrb,
      iA    => iA,
      iB    => iB,
      iC    => iC,
      iD    => iD,
      oD1   => oD1,
      oD2   => oD2,
      oD3   => oD3,
      oStrb => oStrb
    );

  iClk <= not iClk after clk_period/2;

  process
  begin
    wait for 100 * clk_period;

    iStrb <= '1';
    wait for clk_period;
    iStrb <= '0';

    wait;

  end process;

end;