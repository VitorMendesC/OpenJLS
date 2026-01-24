----------------------------------------------------------------------------------
-- Company:
-- Module:      A12_variables_update  (NEAR = 0)
-- Purpose:     JPEG-LS T.87 A.12 variables update in one cycle (keeps A12+A13 same cycle)
-- Notes:       - Rescale when N == RESET
--              - B += Errval (NEAR=0 => factor (2*NEAR+1)=1)
--              - Arithmetic shift for B => floor(B/2) for negatives per T.87
--              - Uses unsigned(abs(iErrorValue)); safe in lossless mode after clamp
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity A12_variables_update is
  generic (
    BITNESS : natural range 8 to 16 := 12;
    A_WIDTH : natural               := 22;
    B_WIDTH : natural               := 16;
    N_WIDTH : natural               := 12;
    RESET   : natural               := 64
  );
  port (
    iErrorValue : in signed (BITNESS downto 0);       -- Errval after correction & clamp
    iAq         : in unsigned (A_WIDTH - 1 downto 0); -- context RAM (registered)
    iBq         : in signed (B_WIDTH - 1 downto 0);
    iNq         : in unsigned (N_WIDTH - 1 downto 0);

    oAq : out unsigned (A_WIDTH - 1 downto 0); -- to context RAM (register outside)
    oBq : out signed (B_WIDTH - 1 downto 0);
    oNq : out unsigned (N_WIDTH - 1 downto 0)
  );
end entity;

architecture rtl of A12_variables_update is

  signal sDoRescale : std_logic;

  signal sErrExtend      : signed (B_WIDTH - 1 downto 0);
  signal sErrorAbsExtend : unsigned(A_WIDTH - 1 downto 0);
  signal sA              : unsigned(A_WIDTH - 1 downto 0);
  signal sB              : signed (B_WIDTH - 1 downto 0);
  signal sN              : unsigned(N_WIDTH - 1 downto 0);
  signal sARescale       : unsigned(A_WIDTH - 1 downto 0);
  signal sBRescale       : signed (B_WIDTH - 1 downto 0);
  signal sNRescale       : unsigned(N_WIDTH - 1 downto 0);

begin

  sDoRescale <= '1' when (iNq = to_unsigned(RESET, iNq'length)) else
    '0';

  sErrExtend      <= resize(iErrorValue, B_WIDTH);
  sErrorAbsExtend <= resize(unsigned(abs(iErrorValue)), A_WIDTH);

  sA <= iAq + sErrorAbsExtend;
  sB <= iBq + sErrExtend;
  sN <= iNq + 1;

  -- Rescale: halve A & B; N sequencing: (N>>1) + 1 (per T.87)
  sARescale <= shift_right(sA, 1);
  sBRescale <= shift_right(sB, 1); -- arithmetic >> 1 => floor for negatives
  sNRescale <= shift_right(iNq, 1) + 1;

  -- Late select (parallel cones + shallow 2:1 muxes)
  oAq <= sARescale when sDoRescale = '1' else
    sA;
  oBq <= sBRescale when sDoRescale = '1' else
    sB;
  oNq <= sNRescale when sDoRescale = '1' else
    sN;

end architecture;
