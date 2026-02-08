----------------------------------------------------------------------------------
-- Company:
-- Engineer:    Vitor Mendes Camilo
-- 
-- Create Date: 02/07/2026
-- Design Name: 
-- Module Name: A23_run_interruption_update - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:                 Code segment A.23
--                                      Update of variables for run interruption sample
-- 
----------------------------------------------------------------------------------

use work.Common.all;

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity A23_run_interruption_update is
  generic (
    A_WIDTH             : natural := CO_AQ_WIDTH_STD;
    N_WIDTH             : natural := CO_NQ_WIDTH_STD;
    ERR_WIDTH           : natural := CO_ERROR_VALUE_WIDTH_STD;
    MAPPED_ERRVAL_WIDTH : natural := CO_MAPPED_ERROR_VAL_WIDTH_STD;
    RESET               : natural := CO_RESET_STD
  );
  port (
    iErrval   : in signed (ERR_WIDTH - 1 downto 0);
    iEMErrval : in unsigned (MAPPED_ERRVAL_WIDTH - 1 downto 0);
    iRItype   : in std_logic;
    iAq       : in unsigned (A_WIDTH - 1 downto 0);
    iNq       : in unsigned (N_WIDTH - 1 downto 0);
    iNn       : in unsigned (N_WIDTH - 1 downto 0);
    oAq       : out unsigned (A_WIDTH - 1 downto 0);
    oNq       : out unsigned (N_WIDTH - 1 downto 0);
    oNn       : out unsigned (N_WIDTH - 1 downto 0)
  );
end A23_run_interruption_update;

architecture Behavioral of A23_run_interruption_update is
begin

  process (iErrval, iEMErrval, iRItype, iAq, iNq, iNn)
    variable vAq : integer;
    variable vNq : integer;
    variable vNn : integer;
    variable vRI : integer;
  begin
    vAq := to_integer(iAq);
    vNq := to_integer(iNq);
    vNn := to_integer(iNn);

    if iErrval < 0 then
      vNn := vNn + 1;
    end if;

    vRi := std_to_int(iRItype);

    vAq := vAq + (to_integer(iEMErrval) + 1 - vRI) / 2;

    if vNq = integer(RESET) then
      vAq := vAq / 2;
      vNq := vNq / 2;
      vNn := vNn / 2;
    end if;

    vNq := vNq + 1;

    oAq <= to_unsigned(vAq, oAq'length);
    oNq <= to_unsigned(vNq, oNq'length);
    oNn <= to_unsigned(vNn, oNn'length);
  end process;

end Behavioral;
