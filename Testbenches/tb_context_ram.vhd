----------------------------------------------------------------------------------
-- Company:
-- Engineer:    Vitor Mendes Camilo
-- 
-- Create Date: 09/04/2025 09:12:23 AM
-- Design Name: 
-- Module Name: tb_context_ram - Behavioral
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

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.Common.all;

entity tb_context_ram is
end;

architecture bench of tb_context_ram is
  -- Clock period
  constant clk_period : time := 5 ns;
  -- Generics
  constant WIDTH   : natural := 4 * 16;
  constant DEPTH   : natural := 367;
  constant MAX_VAL : natural := 4095;
  -- Ports
  signal iClk         : std_logic                             := '1';
  signal iRst         : std_logic                             := '0';
  signal iValid       : std_logic                             := '0';
  signal iWriteEnable : std_logic                             := '0';
  signal iAddrA       : unsigned (clog2(DEPTH) - 1 downto 0)  := (others => '0');
  signal iAddrB       : unsigned (clog2(DEPTH) - 1 downto 0)  := (others => '0');
  signal iData        : std_logic_vector (WIDTH - 1 downto 0) := (others => '0');
  signal oData        : std_logic_vector (WIDTH - 1 downto 0);

  signal sQ : unsigned (8 downto 0);

begin

  iAddrA <= sQ;
  iAddrB <= sQ;

  context_ram_inst : entity work.context_ram
    generic map(
      WIDTH   => WIDTH,
      DEPTH   => DEPTH,
      MAX_VAL => MAX_VAL
    )
    port map
    (
      iClk         => iClk,
      iRst         => iRst,
      iValid       => iValid,
      iWriteEnable => iWriteEnable,
      iAddrA       => iAddrA,
      iAddrB       => iAddrB,
      iData        => iData,
      oData        => oData
    );

  iClk <= not iClk after clk_period/2;

  process
  begin
    wait for 10 * clk_period;
    iRst <= '1';
    wait for clk_period;
    iRst <= '0';

    wait for 10 * clk_period;
    sQ     <= to_unsigned(10, sQ'length);
    iValid <= '1';
    wait for clk_period;
    iValid <= '0';

    wait for 10 * clk_period;
    iWriteEnable <= '1';
    iData        <= std_logic_vector(to_unsigned(133, iData'length));
    wait for 2 * clk_period;
    iWriteEnable <= '0';

    wait for 10 * clk_period;
    sQ     <= to_unsigned(10, sQ'length);
    iValid <= '1';
    wait for clk_period;
    iValid <= '0';

    wait;

  end process;

end;