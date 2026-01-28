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
    BITNESS : natural := CO_BITNESS_STD;
    MAX_VAL : natural := CO_MAX_VAL_STD
  );
  port (
    iPx   : in unsigned (BITNESS - 1 downto 0);
    iSign : in std_logic;
    iCq   : in signed (CO_CQ_WIDTH - 1 downto 0);
    oPx   : out unsigned (BITNESS - 1 downto 0)
  );
end A6_prediction_correction;

architecture Behavioral of A6_prediction_correction is
  constant EXT_WIDTH : natural                        := BITNESS + 2;
  constant ZERO_S    : signed(EXT_WIDTH - 1 downto 0) := (others => '0');
  constant MAX_S     : signed(EXT_WIDTH - 1 downto 0) := to_signed(MAX_VAL, EXT_WIDTH);

  signal sPxPlusCq  : signed (EXT_WIDTH - 1 downto 0);
  signal sPxMinusCq : signed (EXT_WIDTH - 1 downto 0);

  -- Precomputed saturated results (vector-select is shallow)
  signal sAddSat : unsigned (BITNESS - 1 downto 0);
  signal sSubSat : unsigned (BITNESS - 1 downto 0);

begin

  -- Align widths explicitly for portable, predictable arithmetic
  sPxPlusCq  <= resize(signed('0' & iPx), EXT_WIDTH) + resize(iCq, EXT_WIDTH);
  sPxMinusCq <= resize(signed('0' & iPx), EXT_WIDTH) - resize(iCq, EXT_WIDTH);

  -- Saturate add/sub results in parallel
  sAddSat <= (others => '0') when (sPxPlusCq < ZERO_S) else
    TO_UNSIGNED(MAX_VAL, BITNESS) when (sPxPlusCq > MAX_S) else
    unsigned(sPxPlusCq(BITNESS - 1 downto 0));
  sSubSat <= (others => '0') when (sPxMinusCq < ZERO_S) else
    TO_UNSIGNED(MAX_VAL, BITNESS) when (sPxMinusCq > MAX_S) else
    unsigned(sPxMinusCq(BITNESS - 1 downto 0));

  -- Final 2:1 mux by sign
  oPx <= sAddSat when iSign = '0' else
    sSubSat;

end Behavioral;
