----------------------------------------------------------------------------------
-- Company:
-- Engineer:    Vitor Mendes Camilo
-- 
-- Create Date:
-- Design Name: 
-- Module Name: A12_variables_update - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------
use work.Common.all;

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity A12_variables_update is
  generic (
    BITNESS : natural range 8 to 16 := CO_BITNESS_STD;
    A_WIDTH : natural               := CO_AQ_WIDTH_STD;
    B_WIDTH : natural               := CO_BQ_WIDTH_STD;
    N_WIDTH : natural               := CO_NQ_WIDTH_STD;
    RESET   : natural               := CO_RESET_STD;
    NEAR    : natural               := CO_NEAR_STD
  );
  port (
    iErrorVal : in signed (BITNESS downto 0); -- Errval after correction & clamp
    iAq       : in unsigned (A_WIDTH - 1 downto 0); -- context RAM (registered)
    iBq       : in signed (B_WIDTH - 1 downto 0);
    iNq       : in unsigned (N_WIDTH - 1 downto 0);

    oAq : out unsigned (A_WIDTH - 1 downto 0); -- to context RAM (register outside)
    oBq : out signed (B_WIDTH - 1 downto 0);
    oNq : out unsigned (N_WIDTH - 1 downto 0)
  );
end entity;

architecture rtl of A12_variables_update is

  constant C_ERR_SCALE : signed (B_WIDTH - 1 downto 0) := to_signed((2 * NEAR) + 1, B_WIDTH);

  signal sDoRescale      : std_logic;
  signal sErrExtend      : signed (B_WIDTH - 1 downto 0);
  signal sErrScaledWide  : signed ((2 * B_WIDTH) - 1 downto 0);
  signal sErrorAbsExtend : unsigned(A_WIDTH - 1 downto 0);
  signal sAqNew          : unsigned(A_WIDTH - 1 downto 0);
  signal sBqNew          : signed (B_WIDTH - 1 downto 0);
  signal sNqNew          : unsigned(N_WIDTH - 1 downto 0);
  signal sARescale       : unsigned(A_WIDTH - 1 downto 0);
  signal sBRescale       : signed (B_WIDTH - 1 downto 0);
  signal sNRescale       : unsigned(N_WIDTH - 1 downto 0);

begin

  sDoRescale <= '1' when (iNq = to_unsigned(RESET, iNq'length)) else
    '0';

  sErrExtend      <= resize(iErrorVal, B_WIDTH);
  sErrScaledWide  <= sErrExtend * C_ERR_SCALE;
  sErrorAbsExtend <= resize(unsigned(abs(iErrorVal)), A_WIDTH);

  sAqNew <= iAq + sErrorAbsExtend;
  sBqNew <= iBq + resize(sErrScaledWide, B_WIDTH);
  sNqNew <= iNq + 1;

  -- Rescale: halve A & B; N sequencing: (N>>1) + 1 (per T.87)
  sARescale <= shift_right(sAqNew, 1);
  sBRescale <= shift_right(sBqNew, 1); -- arithmetic >> 1 => floor for negatives
  sNRescale <= shift_right(iNq, 1) + 1;

  -- Late select (parallel cones + shallow 2:1 muxes)
  oAq <= sARescale when sDoRescale = '1' else
    sAqNew;
  oBq <= sBRescale when sDoRescale = '1' else
    sBqNew;
  oNq <= sNRescale when sDoRescale = '1' else
    sNqNew;

end architecture;
