----------------------------------------------------------------------------------
  -- Company:
  -- Engineer:    Vitor Mendes Camilo
  --
  -- Create Date: 02/07/2026
  -- Design Name:
  -- Module Name: A2_mode_selection - Behavioral
  -- Project Name:
  -- Target Devices:
  -- Tool Versions:
  -- Description:
  --
  -- Dependencies:
  --
  -- Revision:
  -- Revision 0.01 - File Created
  -- Additional Comments:                 Code segment A.2
  --
  ----------------------------------------------------------------------------------
  use work.common.all;

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity a2_mode_selection is
  generic (
    BITNESS : natural range 8 to 16 := CO_BITNESS_STD;
    NEAR    : natural               := CO_NEAR_STD
  );
  port (
    iD1      : in    signed(BITNESS downto 0);
    iD2      : in    signed(BITNESS downto 0);
    iD3      : in    signed(BITNESS downto 0);
    oModeRun : out   std_logic
  );
end entity a2_mode_selection;

architecture behavioral of a2_mode_selection is

  constant C_NEAR : signed(BITNESS downto 0) := to_signed(NEAR, BITNESS + 1);

begin

  oModeRun <= '1' when (abs(iD1) <= C_NEAR and abs(iD2) <= C_NEAR and abs(iD3) <= C_NEAR) else
              '0';

end architecture behavioral;
