----------------------------------------------------------------------------------
-- Company:
-- Engineer:    Vitor Mendes Camilo
-- 
-- Create Date: 02/07/2026
-- Design Name: 
-- Module Name: A19_run_interruption_error - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:                 Code segment A.19
--                                      Error computation for a run interruption sample
-- 
----------------------------------------------------------------------------------

use work.Common.all;

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity A19_run_interruption_error is
  generic (
    BITNESS : natural range 8 to 16 := CO_BITNESS_STD;
    MAX_VAL : natural               := CO_MAX_VAL_STD;
    NEAR    : natural               := CO_NEAR_STD
  );
  port (
    iErrval : in signed (BITNESS downto 0);
    iPx     : in unsigned (BITNESS - 1 downto 0);
    iRItype : in std_logic;
    iRa     : in unsigned (BITNESS - 1 downto 0);
    iRb     : in unsigned (BITNESS - 1 downto 0);
    iIx     : in unsigned (BITNESS - 1 downto 0);
    oErrval : out signed (BITNESS downto 0);
    oRx     : out unsigned (BITNESS - 1 downto 0);
    oSign   : out std_logic
  );
end A19_run_interruption_error;

architecture Behavioral of A19_run_interruption_error is
  constant C_RANGE : integer := MAX_VAL + 1;
  constant C_SCALE : integer := (2 * NEAR) + 1;

begin

  process (iErrval, iPx, iRItype, iRa, iRb, iIx)
    variable vErr      : integer;
    variable vErrQuant : integer;
    variable vErrAdj   : integer;
    variable vRx       : integer;
    variable vSignMult : integer;
    variable vSign     : std_logic;
  begin
    vErr := to_integer(iErrval);

    if (iRItype = '0') and (iRa > iRb) then
      vErr  := - vErr;
      vSign := CO_SIGN_NEG;
    else
      vSign := CO_SIGN_POS;
    end if;

    if vSign = CO_SIGN_POS then
      vSignMult := 1;
    else
      vSignMult := - 1;
    end if;

    if NEAR > 0 then

      -- Quantize (A.8)
      -- Errval = Quantize(Errval)
      if vErr > 0 then
        vErrQuant := (vErr + NEAR) / C_SCALE;
      else
        vErrQuant := - (NEAR - vErr) / C_SCALE;
      end if;

      -- ComputeRx (A.8)
      -- Rx = ComputeRx()
      vRx := to_integer(iPx) + vSignMult * vErrQuant * C_SCALE;
      if vRx < 0 then
        vRx := 0;
      elsif vRx > MAX_VAL then
        vRx := MAX_VAL;
      end if;
    else
      vErrQuant := vErr;
      vRx       := to_integer(iIx);
    end if;

    -- Modulo reduction (A.9)
    -- Errval = ModRange(Errval)
    vErrAdj := vErrQuant;
    if vErrAdj < 0 then
      vErrAdj := vErrAdj + C_RANGE;
    end if;
    if vErrAdj >= (C_RANGE + 1) / 2 then
      vErrAdj := vErrAdj - C_RANGE;
    end if;

    oErrval <= to_signed(vErrAdj, oErrval'length);
    oRx     <= to_unsigned(vRx, oRx'length);
    oSign   <= vSign;
  end process;

end Behavioral;
