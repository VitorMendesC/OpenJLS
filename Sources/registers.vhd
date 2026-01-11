----------------------------------------------------------------------------------
-- Company:
-- Engineer:    Vitor Mendes Camilo
-- 
-- Create Date: 09/06/2025 08:51:59 PM
-- Design Name: 
-- Module Name: registers - Behavioral
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
library IEEE;
use IEEE.STD_LOGIC_1164.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity registers is
  generic (
    A_WIDTH     : integer := 12;
    B_WIDTH     : integer := 12;
    C_WIDTH     : integer := 12;
    N_WIDTH     : integer := 12;
    BITNESS     : integer := 12;
    ERROR_WIDTH : integer := 13
  );
  port (
    iClk        : in std_logic;
    iRst        : in std_logic;
    iIx         : in std_logic_vector (BITNESS - 1 downto 0);
    iPx         : in std_logic_vector (BITNESS - 1 downto 0);
    iSign       : in std_logic;
    iErrorValue : in std_logic_vector (ERROR_WIDTH - 1 downto 0);
    iAq         : in std_logic_vector (A_WIDTH - 1 downto 0);
    iBq         : in std_logic_vector (B_WIDTH - 1 downto 0);
    iCq         : in std_logic_vector (C_WIDTH - 1 downto 0);
    iNq         : in std_logic_vector (N_WIDTH - 1 downto 0);
    oIx         : out std_logic_vector (BITNESS - 1 downto 0);
    oPx         : out std_logic_vector (BITNESS - 1 downto 0);
    oSign       : out std_logic;
    oErrorValue : out std_logic_vector (ERROR_WIDTH - 1 downto 0);
    oAq         : out std_logic_vector (A_WIDTH - 1 downto 0);
    oCq         : out std_logic_vector (C_WIDTH - 1 downto 0);
    oBq         : out std_logic_vector (B_WIDTH - 1 downto 0);
    oNq         : out std_logic_vector (N_WIDTH - 1 downto 0)
  );
end registers;

architecture Behavioral of registers is

begin

  process (iClk)
  begin
    if rising_edge(iClk) then
      if iRst = '1' then
        oAq         <= (others => '0');
        oBq         <= (others => '0');
        oCq         <= (others => '0');
        oNq         <= (others => '0');
        oErrorValue <= (others => '0');
      else
        oAq         <= iAq;
        oBq         <= iBq;
        oCq         <= iCq;
        oNq         <= iNq;
        oErrorValue <= iErrorValue;
      end if;
    end if;
  end process;
end Behavioral;
