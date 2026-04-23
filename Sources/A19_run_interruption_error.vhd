----------------------------------------------------------------------------------
-- Engineer:    Vitor Mendes Camilo
--
-- Module Name: A19_run_interruption_error - Behavioral
-- Description: Code segment A.19 — error computation for run-interruption
--              sample (lossless only).
--
--              With NEAR=0, the T.87 Quantize() step is identity and
--              Rx = Ix, so no reconstruction is produced here. Only:
--                - sign flip when RItype=0 and Ra > Rb
--                - modulo reduction (A.9 inlined)
----------------------------------------------------------------------------------

use work.Common.all;

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity A19_run_interruption_error is
  generic (
    BITNESS : natural range 8 to 16 := CO_BITNESS_STD;
    MAX_VAL : natural               := CO_MAX_VAL_STD
  );
  port (
    iErrval : in signed (BITNESS downto 0);
    iRItype : in std_logic;
    iRa     : in unsigned (BITNESS - 1 downto 0);
    iRb     : in unsigned (BITNESS - 1 downto 0);
    oErrval : out signed (BITNESS downto 0);
    oSign   : out std_logic
  );
end A19_run_interruption_error;

architecture Behavioral of A19_run_interruption_error is
  constant C_RANGE : integer := MAX_VAL + 1;
begin

  process (iErrval, iRItype, iRa, iRb)
    variable vErr    : integer;
    variable vErrAdj : integer;
  begin
    -- Sign adjustment: RItype=0 and Ra > Rb → negate error
    if iRItype = '0' and iRa > iRb then
      vErr  := - to_integer(iErrval);
      oSign <= CO_SIGN_NEG;
    else
      vErr  := to_integer(iErrval);
      oSign <= CO_SIGN_POS;
    end if;

    -- Modulo reduction (A.9 inline)
    vErrAdj := vErr;
    if vErrAdj < 0 then
      vErrAdj := vErrAdj + C_RANGE;
    end if;
    if vErrAdj >= (C_RANGE + 1) / 2 then
      vErrAdj := vErrAdj - C_RANGE;
    end if;

    oErrval <= to_signed(vErrAdj, oErrval'length);
  end process;

end Behavioral;
