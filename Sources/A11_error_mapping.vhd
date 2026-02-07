----------------------------------------------------------------------------------
-- Company:
-- Engineer:    Vitor Mendes Camilo
-- 
-- Create Date: 08/30/2025 12:02:02 AM
-- Design Name: 
-- Module Name: A11_error_mapping - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision: 
-- Revision 0.01 - File Created
-- Additional Comments:             Code segment A.11
--                                  Error mapping to non-negative values
--
-- NOTE: if N_WIDTH > B_WIDTH the code is wrong and will overflow
----------------------------------------------------------------------------------
use work.Common.all;

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity A11_error_mapping is
  generic (
    BITNESS                : natural := CO_BITNESS_STD;
    N_WIDTH                : natural := CO_NQ_WIDTH_STD;
    B_WIDTH                : natural := CO_BQ_WIDTH_STD;
    K_WIDTH                : natural := CO_K_WIDTH_STD;
    ERROR_VALUE_WIDTH      : natural := CO_ERROR_VALUE_WIDTH_STD;
    MAPPED_ERROR_VAL_WIDTH : natural := CO_MAPPED_ERROR_VAL_WIDTH_STD;
    NEAR                   : natural := CO_NEAR_STD
  );
  port (
    iK              : in unsigned (K_WIDTH - 1 downto 0);
    iBq             : in signed (B_WIDTH - 1 downto 0);
    iNq             : in unsigned (N_WIDTH - 1 downto 0);
    iErrorVal       : in signed (ERROR_VALUE_WIDTH - 1 downto 0);
    oMappedErrorVal : out unsigned (MAPPED_ERROR_VAL_WIDTH - 1 downto 0)
  );
end A11_error_mapping;

architecture Behavioral of A11_error_mapping is
  -- Control flags
  signal sSpecialMap          : std_logic;
  signal sErrEqualGreaterZero : std_logic;

  -- Width-extended compare for 2*B <= -N (avoid overflow and mismatched lengths)
  signal sBExt        : signed(B_WIDTH downto 0);
  signal sNExt        : signed(B_WIDTH downto 0);
  signal sErrorValExt : signed((2 * MAPPED_ERROR_VAL_WIDTH) - 1 downto 0); -- so that abs(ErrorVal) fits

  -- Precomputed mapping candidates (parallel)
  signal sErrU, sErrAbsU     : unsigned (oMappedErrorVal'range);
  signal sMapErrorSpecialPos : unsigned (oMappedErrorVal'range);
  signal sMapErrorSpecialNeg : unsigned (oMappedErrorVal'range);
  signal sMapErrorRegPos     : unsigned (oMappedErrorVal'range);
  signal sMapErrorRegNeg     : unsigned (oMappedErrorVal'range);

begin

  assert B_WIDTH >= N_WIDTH
  report "A11_error_mapping: B_WIDTH must be >= N_WIDTH, else it may overflow!"
    severity failure;

  sErrorValExt <= resize(iErrorVal, sErrorValExt'length);
  -- Extend and compare: 2*B <= -N with one extra bit to prevent overflow
  sBExt <= resize(iBq, sBExt'length);
  sNExt <= resize(signed(iNq), sBExt'length);

  sSpecialMap <= '1' when (NEAR = 0 and iK = 0 and 2 * sBExt <= - sNExt) else
    '0';

  -- Error sign flag
  sErrEqualGreaterZero <= '1' when iErrorVal >= 0 else
    '0';

  -- Magnitudes for mapping
  sErrU    <= resize(unsigned(iErrorVal), sErrU'length); -- Only used when ErrorVal >= 0, conversion is safe
  sErrAbsU <= resize(unsigned(abs(sErrorValExt)), sErrAbsU'length);

  -- Special mapping
  sMapErrorSpecialPos <= resize((2 * sErrU) + 1, sMapErrorSpecialPos'length);
  sMapErrorSpecialNeg <= resize((2 * sErrAbsU) - 2, sMapErrorSpecialNeg'length);

  -- Regular mapping
  sMapErrorRegPos <= resize(2 * sErrU, sMapErrorRegPos'length);
  sMapErrorRegNeg <= resize((2 * sErrAbsU) - 1, sMapErrorRegNeg'length);

  -- Final selection (purely combinational)
  oMappedErrorVal <= sMapErrorSpecialPos when (sSpecialMap = '1' and sErrEqualGreaterZero = '1') else
    sMapErrorSpecialNeg when (sSpecialMap = '1' and sErrEqualGreaterZero = '0') else
    sMapErrorRegPos when (sSpecialMap = '0' and sErrEqualGreaterZero = '1') else
    sMapErrorRegNeg; -- last case (Errval<0)

end Behavioral;
