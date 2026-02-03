----------------------------------------------------------------------------------
-- Company:
-- Engineer:    Vitor Mendes Camilow
-- 
-- Create Date:
-- Design Name: 
-- Module Name: A13_update_bias - Behavioral
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

entity A13_update_bias is
  generic (
    B_WIDTH : natural := CO_BQ_WIDTH_STD;
    N_WIDTH : natural := CO_NQ_WIDTH_STD;
    C_WIDTH : natural := CO_CQ_WIDTH;
    MIN_C   : integer := CO_MIN_CQ;
    MAX_C   : integer := CO_MAX_CQ
  );
  port (
    iBq : in signed (B_WIDTH - 1 downto 0);
    iNq : in unsigned (N_WIDTH - 1 downto 0);
    iCq : in signed (C_WIDTH - 1 downto 0);
    oBq : out signed (B_WIDTH - 1 downto 0);
    oCq : out signed (C_WIDTH - 1 downto 0)
  );
end entity A13_update_bias;

architecture rtl of A13_update_bias is

  -- Common constants
  constant ZERO_B : signed(B_WIDTH - 1 downto 0) := (others => '0');

  -- Parallel computations (no clock, no process)
  signal sN          : signed(B_WIDTH - 1 downto 0);
  signal sNegThr     : signed(B_WIDTH - 1 downto 0);
  signal sNegThrP1   : signed(B_WIDTH - 1 downto 0);
  signal sBPlusN     : signed(B_WIDTH - 1 downto 0);
  signal sBMinusN    : signed(B_WIDTH - 1 downto 0);
  signal sIsNegBand  : std_logic;
  signal sIsPosBand  : std_logic;
  signal sNeedNegClp : std_logic;
  signal sNeedPosClp : std_logic;
  signal sBNegFinal  : signed(B_WIDTH - 1 downto 0);
  signal sBPosFinal  : signed(B_WIDTH - 1 downto 0);
  signal sCDec       : unsigned(C_WIDTH - 1 downto 0);
  signal sCInc       : unsigned(C_WIDTH - 1 downto 0);

begin

  -- Extend N to B width for signed math
  sN <= signed(resize(iNq, B_WIDTH));

  -- Precompute thresholds and candidates
  sNegThr   <= - sN; -- -N
  sNegThrP1 <= (-sN) + 1; -- -N + 1
  sBPlusN   <= iBq + sN; -- B + N
  sBMinusN  <= iBq - sN; -- B - N

  -- Band selection (equivalent to if/else-if)
  sIsNegBand <= '1' when (iBq <= sNegThr) else
    '0';
  sIsPosBand <= '1' when (iBq > ZERO_B) else
    '0';

  -- C update candidates with saturation to [MIN_C .. MAX_C]
  sCDec <= (iCq - 1) when (iCq > MIN_C) else
    iCq; -- if (C>MIN_C) C--
  sCInc <= (iCq + 1) when (iCq < MAX_C) else
    iCq; -- if (C<MAX_C) C++

  -- B clamping after update
  sNeedNegClp <= '1' when (sBPlusN <= sNegThr) else
    '0'; -- if (B+N <= -N) => B=-N+1
  sNeedPosClp <= '1' when (sBMinusN > ZERO_B) else
    '0'; -- if (B-N > 0)  => B=0

  sBNegFinal <= sNegThrP1 when (sNeedNegClp = '1') else
    sBPlusN;
  sBPosFinal <= ZERO_B when (sNeedPosClp = '1') else
    sBMinusN;

  -- Final select (no process: pure parallel logic)
  oBq <= sBNegFinal when (sIsNegBand = '1') else
    sBPosFinal when (sIsPosBand = '1') else
    iBq;

  oCq <= sCDec when (sIsNegBand = '1') else
    sCInc when (sIsPosBand = '1') else
    iCq;

end architecture rtl;
