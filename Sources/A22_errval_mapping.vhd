----------------------------------------------------------------------------------
-- Company:
-- Engineer:    Vitor Mendes Camilo
-- 
-- Create Date: 02/07/2026
-- Design Name: 
-- Module Name: A22_errval_mapping - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:                 Code segment A.22
--                                      Errval mapping for run interruption sample
-- 
----------------------------------------------------------------------------------

use work.Common.all;

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity A22_errval_mapping is
  generic (
    ERR_WIDTH           : natural := CO_ERROR_VALUE_WIDTH_STD;
    MAPPED_ERRVAL_WIDTH : natural := CO_MAPPED_ERROR_VAL_WIDTH_STD
  );
  port (
    iErrval   : in signed (ERR_WIDTH - 1 downto 0);
    iRItype   : in std_logic;
    iMap      : in std_logic;
    oEMErrval : out unsigned (MAPPED_ERRVAL_WIDTH - 1 downto 0)
  );
end A22_errval_mapping;

architecture Behavioral of A22_errval_mapping is
begin

  process (iErrval, iRItype, iMap)
    variable vRI       : integer;
    variable vMap      : integer;
    variable vEmErrval : integer;
  begin

    vRi  := std_to_int(iRItype);
    vMap := std_to_int(iMap);

    vEmErrval := 2 * abs(to_integer(iErrval)) - vRI - vMap;

    oEMErrval <= to_unsigned(vEmErrval, oEMErrval'length);
  end process;

end Behavioral;
