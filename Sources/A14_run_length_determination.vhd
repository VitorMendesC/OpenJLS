----------------------------------------------------------------------------------
-- Company:
-- Engineer:    Vitor Mendes Camilo
-- 
-- Create Date: 02/07/2026
-- Design Name: 
-- Module Name: A14_run_length_determination - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:                 Code segment A.14
--                                      Run-length determination for run mode
--
-- TODO: Has to be fed RunCnt from the previous cycle. Which needs to be reseted when oRunContinue = '0';
----------------------------------------------------------------------------------

use work.Common.all;

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity A14_run_length_determination is
  generic (
    BITNESS       : natural range 8 to 16 := CO_BITNESS_STD;
    RUN_CNT_WIDTH : natural               := 16;
    NEAR          : natural               := CO_NEAR_STD
  );
  port (
    iRa          : in unsigned (BITNESS - 1 downto 0);
    iIx          : in unsigned (BITNESS - 1 downto 0);
    iRunCnt      : in unsigned (RUN_CNT_WIDTH - 1 downto 0);
    iEOL         : in std_logic;
    oRunCnt      : out unsigned (RUN_CNT_WIDTH - 1 downto 0);
    oRx          : out unsigned (BITNESS - 1 downto 0);
    oRunHit      : out std_logic;
    oRunContinue : out std_logic
  );
end A14_run_length_determination;

architecture Behavioral of A14_run_length_determination is
begin

  process (iRa, iIx, iRunCnt, iEOL)
    variable vDiffIxRa : integer;
    variable vCnt      : unsigned (RUN_CNT_WIDTH - 1 downto 0);
    variable vRunHit   : std_logic;
  begin
    vDiffIxRa := abs(to_integer(iIx) - to_integer(iRa));

    if vDiffIxRa <= integer(NEAR) then
      vRunHit := '1';
      vCnt    := iRunCnt + 1;
    else
      vRunHit := '0';
      vCnt    := iRunCnt;
    end if;

    oRunCnt <= vCnt;
    oRx     <= iRa; -- Valid when oRunHit='1'
    oRunHit <= vRunHit;

    if (vRunHit = '1') and (iEOL = '0') then
      oRunContinue <= '1';
    else
      oRunContinue <= '0';
    end if;
  end process;

end Behavioral;
