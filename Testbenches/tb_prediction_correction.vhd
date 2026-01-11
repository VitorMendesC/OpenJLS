
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity prediction_correction_tb is
end;

architecture bench of prediction_correction_tb is
  -- Clock period
  constant clk_period : time := 5 ns;
  -- Generics
  constant BITNESS : natural range 8 to 16    := 12;
  constant MAX_VAL : natural range 0 to 65535 := 4095;
  -- Ports
  signal iClk  : std_logic;
  signal iStrb : std_logic;
  signal iPx   : unsigned (BITNESS - 1 downto 0);
  signal iSign : std_logic;
  signal iCq   : unsigned (BITNESS - 1 downto 0);
  signal oStrb : std_logic;
  signal oPx   : unsigned (BITNESS - 1 downto 0);
begin

  prediction_correction_inst : entity work.prediction_correction
    generic map(
      BITNESS => BITNESS,
      MAX_VAL => MAX_VAL
    )
    port map
    (
      iClk  => iClk,
      iStrb => iStrb,
      iPx   => iPx,
      iSign => iSign,
      iCq   => iCq,
      oStrb => oStrb,
      oPx   => oPx
    );
  -- clk <= not clk after clk_period/2;

end;