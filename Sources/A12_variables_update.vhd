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
-- Assumptions:
--                 B_WIDTH  >=  C_ERR_SCALED_WIDTH
-- 
----------------------------------------------------------------------------------
use work.Common.all;

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity A12_variables_update is
  generic (
    BITNESS : natural := CO_BITNESS_STD;
    A_WIDTH : natural := CO_AQ_WIDTH_STD;
    B_WIDTH : natural := CO_BQ_WIDTH_STD;
    N_WIDTH : natural := CO_NQ_WIDTH_STD;
    RESET   : natural := CO_RESET_STD;
    NEAR    : natural := CO_NEAR_STD
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

  constant C_ERR_IN_WIDTH     : natural                             := BITNESS + 1;
  constant C_SCALE_WIDTH      : natural                             := 10; -- 2*255+1 = 511 (max, fits in 10b)
  constant C_ERR_SCALED_WIDTH : natural                             := C_ERR_IN_WIDTH + C_SCALE_WIDTH;
  constant C_ERR_SCALE        : signed (C_SCALE_WIDTH - 1 downto 0) := to_signed((2 * NEAR) + 1, C_SCALE_WIDTH);

  signal sDoRescale      : std_logic;
  signal sErrScaledWide  : signed (C_ERR_SCALED_WIDTH - 1 downto 0);
  signal sErrorAbsExtend : unsigned(A_WIDTH - 1 downto 0);
  signal sAqNew          : unsigned(A_WIDTH - 1 downto 0);
  signal sBqNew          : signed (B_WIDTH - 1 downto 0);
  signal sNqNew          : unsigned(N_WIDTH - 1 downto 0);
  signal sARescale       : unsigned(A_WIDTH - 1 downto 0);
  signal sBRescale       : signed (B_WIDTH - 1 downto 0);
  signal sNRescale       : unsigned(N_WIDTH - 1 downto 0);

begin

  assert B_WIDTH >= C_ERR_SCALED_WIDTH
    report "A12: B_WIDTH must be >= C_ERR_SCALED_WIDTH to avoid truncation"
    severity failure;

  sDoRescale <= '1' when (iNq = to_unsigned(RESET, iNq'length)) else
    '0';

  -- Keep this multiply narrow: (BITNESS+1) x 10, then resize to B width.
  sErrScaledWide  <= iErrorVal * C_ERR_SCALE;
  sErrorAbsExtend <= resize(unsigned(abs(iErrorVal)), A_WIDTH);

  sAqNew <= iAq + sErrorAbsExtend;
  sBqNew <= iBq + resize(sErrScaledWide, B_WIDTH);
  sNqNew <= iNq + 1;

  -- Rescale: halve A & B; N sequencing: (N>>1) + 1 (per T.87)
  sARescale <= shift_right(sAqNew, 1);
  sBRescale <= shift_right(sBqNew, 1); -- arithmetic >> 1 => floor for negatives
  sNRescale <= shift_right(iNq, 1) + 1;

  oAq <= sARescale when sDoRescale = '1' else
    sAqNew;
  oBq <= sBRescale when sDoRescale = '1' else
    sBqNew;
  oNq <= sNRescale when sDoRescale = '1' else
    sNqNew;

end architecture;
