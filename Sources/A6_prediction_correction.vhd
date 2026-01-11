----------------------------------------------------------------------------------
-- Company:
-- Engineer:    Vitor Mendes Camilo
-- 
-- Create Date: 08/24/2025 02:31:55 PM
-- Design Name: 
-- Module Name: prediction_correction - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description:                       
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:                 Code segment A.6
--                                      Prediction correction from the bias
-- 
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use work.Common.all;

entity A6_prediction_correction is
  generic (
    BITNESS : natural := 12;
    C_WIDTH : natural := 18;
    MAX_VAL : natural := 4095
  );
  port (
    iPx   : in unsigned (BITNESS - 1 downto 0);
    iSign : in std_logic;
    iCq   : in unsigned (C_WIDTH - 1 downto 0);
    oPx   : out unsigned (BITNESS - 1 downto 0)
  );
end A6_prediction_correction;

architecture Behavioral of A6_prediction_correction is
  signal sPxPluxCq  : unsigned (BITNESS downto 0);
  signal sPxMinusCq : signed (BITNESS downto 0);

  signal sGreater : std_logic;
  signal sLess    : std_logic;

  -- Precomputed saturated results (vector-select is shallow)
  signal sAddSat : unsigned (BITNESS - 1 downto 0);
  signal sSubSat : unsigned (BITNESS - 1 downto 0);

begin

  -- Align widths explicitly for portable, predictable arithmetic
  sPxPluxCq  <= unsigned('0' & iPx) + resize(iCq, sPxPluxCq'length);
  sPxMinusCq <= signed('0' & iPx) - resize(signed(iCq), sPxMinusCq'length);

  -- Cheap overflow/underflow flags (use the extended MSB/sign bit)
  sGreater <= sPxPluxCq(BITNESS);
  sLess    <= sPxMinusCq(BITNESS);

  -- Saturate add/sub results in parallel
  sAddSat <= sPxPluxCq(BITNESS - 1 downto 0) when (sGreater = '0') else
    TO_UNSIGNED(MAX_VAL, BITNESS);
  sSubSat <= unsigned(sPxMinusCq(BITNESS - 1 downto 0)) when (sLess = '0') else
    (others => '0');

  -- Final 2:1 mux by sign
  oPx <= sAddSat when iSign = '0' else
    sSubSat;

end Behavioral;
