
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_jpeg_top is
end;

architecture bench of tb_jpeg_top is
  -- Clock period
  constant clk_period : time := 5 ns;
  -- Generics
  constant BITNESS      : natural range 8 to 16 := 12;
  constant OUT_WIDTH    : natural               := 32;
  constant BUFFER_WIDTH : natural               := 64;
  -- Ports
  signal iClk       : std_logic                               := '1';
  signal iRst       : std_logic                               := '0';
  signal iPixel     : std_logic_vector (BITNESS - 1 downto 0) := (others => '0');
  signal iValid     : std_logic                               := '0';
  signal iA         : std_logic_vector (BITNESS - 1 downto 0) := (others => '0');
  signal iB         : std_logic_vector (BITNESS - 1 downto 0) := (others => '0');
  signal iC         : std_logic_vector (BITNESS - 1 downto 0) := (others => '0');
  signal iD         : std_logic_vector (BITNESS - 1 downto 0) := (others => '0');
  signal oWord      : std_logic_vector (OUT_WIDTH - 1 downto 0);
  signal oWordValid : std_logic;
begin

  jpeg_top_inst : entity work.jpeg_top
    generic map(
      BITNESS      => BITNESS,
      OUT_WIDTH    => OUT_WIDTH,
      BUFFER_WIDTH => BUFFER_WIDTH
    )
    port map
    (
      iClk       => iClk,
      iRst       => iRst,
      iPixel     => iPixel,
      iValid     => iValid,
      iA         => iA,
      iB         => iB,
      iC         => iC,
      iD         => iD,
      oWord      => oWord,
      oWordValid => oWordValid
    );

  iClk <= not iClk after clk_period/2;

  process
  begin
    wait for 10 * clk_period;
    iRst <= '1';
    wait for clk_period;
    iRst <= '0';

    wait for 10 * clk_period;
    iValid <= '1';
    iPixel <= std_logic_vector(to_unsigned(2000, BITNESS));
    iA     <= std_logic_vector(to_unsigned(0, BITNESS));
    iB     <= std_logic_vector(to_unsigned(500, BITNESS));
    iC     <= std_logic_vector(to_unsigned(1000, BITNESS));
    iD     <= std_logic_vector(to_unsigned(1500, BITNESS));
    wait for clk_period;
    iValid <= '0';

    wait;

  end process;

end;