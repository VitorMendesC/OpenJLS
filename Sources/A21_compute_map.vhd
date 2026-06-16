----------------------------------------------------------------------------------
-- Company:
-- Engineer:    Vitor Mendes Camilo
--
-- Create Date: 02/07/2026
-- Design Name:
-- Module Name: A21_compute_map - Behavioral
-- Project Name:
-- Target Devices:
-- Tool Versions:
-- Description:
--
-- Dependencies:
--
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:                 Code segment A.21
--                                      Computation of map for Errval mapping
--
----------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.openjls_pkg.all;

entity a21_compute_map is
  generic (
    K_WIDTH     : natural := CO_K_WIDTH_STD;
    N_WIDTH     : natural := CO_NQ_WIDTH_STD;
    ERROR_WIDTH : natural := CO_ERROR_VALUE_WIDTH_STD
  );
  port (
    iK          : in    unsigned (K_WIDTH - 1 downto 0);
    iErrval     : in    signed (ERROR_WIDTH - 1 downto 0);
    iNn         : in    unsigned (N_WIDTH - 1 downto 0);
    iNq         : in    unsigned (N_WIDTH - 1 downto 0);
    oMap        : out   std_logic
  );
end entity a21_compute_map;

architecture behavioral of a21_compute_map is

  signal sNnExt : unsigned (N_WIDTH downto 0);
  signal sNqExt : unsigned (N_WIDTH downto 0);

begin

  sNnExt <= resize(iNn, sNnExt'length);
  sNqExt <= resize(iNq, sNqExt'length);

  p_compute_map : process (iK, iErrval, sNnExt, sNqExt) is

    variable vMap : std_logic;

  begin

    if ((iK = 0) and (iErrval > 0) and (shift_left(sNnExt, 1) < sNqExt)) then
      vMap := '1';
    elsif ((iErrval < 0) and (shift_left(sNnExt, 1) >= sNqExt)) then
      vMap := '1';
    elsif ((iErrval < 0) and (iK /= 0)) then
      vMap := '1';
    else
      vMap := '0';
    end if;

    oMap <= vMap;

  end process p_compute_map;

end architecture behavioral;
