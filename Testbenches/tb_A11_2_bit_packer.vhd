
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.Common.all;

entity A11_2_bit_packer_tb is
end;

architecture bench of A11_2_bit_packer_tb is
  -- Clock period
  constant clk_period : time := 5 ns;
  -- Generics
  constant LIMIT           : natural := 32;
  constant OUT_WIDTH       : natural := 72;
  constant BUFFER_WIDTH    : natural := 96;
  constant UNARY_WIDTH     : natural := 6;
  constant SUFFIX_WIDTH    : natural := 16;
  constant SUFFIXLEN_WIDTH : natural := 5;
  -- Ports
  signal iClk            : std_logic := '1';
  signal iRst            : std_logic := '0';
  signal iFlush          : std_logic := '0';
  signal iValid          : std_logic := '0';
  signal iUnaryZeros     : unsigned(UNARY_WIDTH - 1 downto 0);
  signal iSuffixLen      : unsigned(SUFFIXLEN_WIDTH - 1 downto 0);
  signal iSuffixVal      : unsigned(SUFFIX_WIDTH - 1 downto 0);
  signal iReady          : std_logic := '0';
  signal oWord           : std_logic_vector(OUT_WIDTH - 1 downto 0);
  signal oWordValid      : std_logic;
  signal oBufferOverflow : std_logic;
begin

  A11_2_bit_packer_inst : entity work.A11_2_bit_packer
    generic map(
      LIMIT           => LIMIT,
      OUT_WIDTH       => OUT_WIDTH,
      BUFFER_WIDTH    => BUFFER_WIDTH,
      UNARY_WIDTH     => UNARY_WIDTH,
      SUFFIX_WIDTH    => SUFFIX_WIDTH,
      SUFFIXLEN_WIDTH => SUFFIXLEN_WIDTH
    )
    port map
    (
      iClk            => iClk,
      iRst            => iRst,
      iFlush          => iFlush,
      iValid          => iValid,
      iUnaryZeros     => iUnaryZeros,
      iSuffixLen      => iSuffixLen,
      iSuffixVal      => iSuffixVal,
      iReady          => iReady,
      oWord           => oWord,
      oWordValid      => oWordValid,
      oBufferOverflow => oBufferOverflow
    );

  iClk <= not iClk after clk_period/2;

  process

    procedure encoded_pixel(val : integer) is
    begin
      wait for 10 * clk_period;
      iValid      <= '1';
      iUnaryZeros <= to_unsigned(19, iUnaryZeros'length);
      iSuffixLen  <= to_unsigned(12, iSuffixLen'length);
      iSuffixVal  <= to_unsigned(val, iSuffixVal'length);
      wait for clk_period;
      iValid <= '0';
    end procedure;

  begin

    wait for 10 * clk_period;
    iRst <= '1';
    wait for clk_period;
    iRst <= '0';

    encoded_pixel(3989);

    wait for 10 * clk_period;
    iReady <= '1';
    wait for clk_period;
    iReady <= '0';

    encoded_pixel(3990);
    encoded_pixel(3988);
    encoded_pixel(3991);

    wait for 20 * clk_period;
    iReady <= '1';
    wait for 3 * clk_period;
    iReady <= '0';

    encoded_pixel(3990);
    encoded_pixel(3988);
    encoded_pixel(3991);

    wait for 10 * clk_period;
    iReady <= '1';
    wait for 3 * clk_period;
    iReady <= '0';

    wait;

  end process;

end;