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
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity A11_error_mapping is
  generic (
    BITNESS : natural range 8 to 16 := 12;
    N_WIDTH : natural               := 7;
    B_WIDTH : natural               := 19;
    K_WIDTH : natural               := 4
  );
  port (
    iK           : in unsigned (K_WIDTH - 1 downto 0);
    iBq          : in signed (B_WIDTH - 1 downto 0);
    iNq          : in unsigned (N_WIDTH - 1 downto 0);
    iErrorValue  : in signed (BITNESS downto 0);
    oMappedError : out unsigned (BITNESS downto 0)
  );
end A11_error_mapping;

architecture Behavioral of A11_error_mapping is
  -- Control flags
  signal sSpecialMap          : std_logic;
  signal sErrEqualGreaterZero : std_logic;

  -- Width-extended compare for 2*B <= -N (avoid overflow and mismatched lengths)
  signal sB_ext   : signed(B_WIDTH downto 0);
  signal sN_ext   : signed(B_WIDTH downto 0);
  signal sB_twice : signed(B_WIDTH downto 0);
  signal sNegN    : signed(B_WIDTH downto 0);

  -- Precomputed mapping candidates (parallel)
  signal sErrU, sErrAbsU     : unsigned (oMappedError'range);
  signal sMapErrorSpecialPos : unsigned (oMappedError'range);
  signal sMapErrorSpecialNeg : unsigned (oMappedError'range);
  signal sMapErrorRegPos     : unsigned (oMappedError'range);
  signal sMapErrorRegNeg     : unsigned (oMappedError'range);

begin

  -- Extend and compare: 2*B <= -N with one extra bit to prevent overflow
  sB_ext   <= resize(iBq, sB_ext'length);
  sN_ext   <= resize(signed(iNq), sN_ext'length);
  sB_twice <= shift_left(sB_ext, 1);
  sNegN    <= - sN_ext;

  sSpecialMap <= '1' when (iK = 0 and sB_twice <= sNegN) else
    '0'; -- NEAR=0 for this IP

  -- Error sign flag
  sErrEqualGreaterZero <= '1' when iErrorValue >= 0 else
    '0';

  -- Magnitudes for mapping
  sErrU    <= unsigned(iErrorValue);
  sErrAbsU <= unsigned(abs(iErrorValue));

  -- Special mapping
  sMapErrorSpecialPos <= shift_left(sErrU, 1) + 1;    -- 2*Errval + 1
  sMapErrorSpecialNeg <= shift_left(sErrAbsU, 1) - 2; -- -2*(Errval+1) = 2*abs(Errval) - 2

  -- Regular mapping
  sMapErrorRegPos <= shift_left(sErrU, 1);        -- 2*Errval
  sMapErrorRegNeg <= shift_left(sErrAbsU, 1) - 1; -- -2*Errval - 1 = 2*abs(Errval) - 1

  -- Final selection (purely combinational)
  oMappedError <= sMapErrorSpecialPos when (sSpecialMap = '1' and sErrEqualGreaterZero = '1') else
    sMapErrorSpecialNeg when (sSpecialMap = '1' and sErrEqualGreaterZero = '0') else
    sMapErrorRegPos when (sSpecialMap = '0' and sErrEqualGreaterZero = '1') else
    sMapErrorRegNeg; -- last case (Errval<0)

end Behavioral;
