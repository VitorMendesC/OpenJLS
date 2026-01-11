----------------------------------------------------------------------------------
-- Company:
-- Engineer:    Vitor Mendes Camilo
-- 
-- Create Date: 09/06/2025 05:43:50 PM
-- Design Name: 
-- Module Name: lutram_simple_dual_port - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description:             LUTRAM, simple dual port, async read, sync write
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
--
--                          NOTE: Mostly made by ChatGPT                          
--
----------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.Common.all;

entity lutram_sdp is
  generic (
    WIDTH      : positive := 44;
    DEPTH      : positive := 366;
    ADDR_WIDTH : positive := clog2(DEPTH)
  );
  port (
    -- Write port (synchronous)
    iClk    : in std_logic;
    iWrEn   : in std_logic;
    iWrAddr : in unsigned(ADDR_WIDTH - 1 downto 0);
    iData   : in std_logic_vector(WIDTH - 1 downto 0);
    -- Read port (asynchronous / combinational)
    iRdAddr : in unsigned(ADDR_WIDTH - 1 downto 0);
    oData   : out std_logic_vector(WIDTH - 1 downto 0)
  );
end entity;

architecture rtl of lutram_sdp is

  type ram_type is array (0 to DEPTH - 1) of std_logic_vector(WIDTH - 1 downto 0);
  signal sRam    : ram_type := (others => (others => '0')); -- optional power-up init
  signal sMemOut : std_logic_vector(WIDTH - 1 downto 0);

begin

  -- ASYNC READ, handles collision
  sMemOut <= sRam(to_integer(iRdAddr));
  oData   <= iData when (iWrEn = '1' and (iWrAddr = iRdAddr)) else
    sMemOut;

  -- SYNC WRITE
  process (iClk)
  begin
    if rising_edge(iClk) then
      if iWrEn = '1' then
        sRam(to_integer(iWrAddr)) <= iData;
      end if;
    end if;
  end process;

end architecture;