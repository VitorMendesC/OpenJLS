----------------------------------------------------------------------------------
-- Company:
-- Engineer:    Vitor Mendes Camilo
-- 
-- Create Date: 09/02/2025 10:25:00 PM
-- Design Name: 
-- Module Name: synchronous_fifo - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description:             Synchronous FIFO
--
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
--                          NOTE: Completely made by ChatGPT, test everything!
-- 
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use work.Common.all;

entity fifo_sync is
  generic (
    WIDTH : positive := 32;
    DEPTH : positive := 1024 -- power of 2 simplifies pointers
  );
  port (
    iClk : in std_logic;
    iRst : in std_logic := '0'; -- synchronous reset

    -- write
    iWrEn : in std_logic;
    iData : in std_logic_vector(WIDTH - 1 downto 0);
    oFull : out std_logic;

    -- read
    iRdEn  : in std_logic;
    oData  : out std_logic_vector(WIDTH - 1 downto 0);
    oEmpty : out std_logic
  );
end;

architecture rtl of fifo_sync is
  constant ADRESS_WIDTH : natural                         := integer(clog2(DEPTH));
  signal wptr, rptr     : unsigned(ADRESS_WIDTH downto 0) := (others => '0'); -- MSB=wrap
  signal ra             : unsigned(ADRESS_WIDTH - 1 downto 0);
  signal wa             : unsigned(ADRESS_WIDTH - 1 downto 0);

begin

  wa <= wptr(ADRESS_WIDTH - 1 downto 0);
  ra <= rptr(ADRESS_WIDTH - 1 downto 0);

  -- memory: one port write, one port read
  tdp_ram : entity work.true_dual_port_ram
    generic map(
      WIDTH    => WIDTH,
      DEPTH    => DEPTH,
      RDW_MODE => "READ_FIRST")
    port map
    (
      clka  => iClk,
      ena   => '1',
      wea   => iWrEn,
      addra => wa,
      dina  => iData,
      douta => open,
      clkb  => iClk,
      enb   => '1',
      web   => '0',
      addrb => ra,
      dinb => (others => '0'),
      doutb => oData
    );

  process (iClk)
  begin
    if rising_edge(iClk) then
      if iRst = '1' then
        wptr <= (others => '0');
        rptr <= (others => '0');
      else
        if (iWrEn = '1') and (oFull = '0') then
          wptr <= wptr + 1;
        end if;
        if (iRdEn = '1') and (oEmpty = '0') then
          rptr <= rptr + 1;
        end if;
      end if;
    end if;
  end process;

  oEmpty <= '1' when wptr = rptr else
    '0';
  oFull <= '1' when (wptr(ADRESS_WIDTH) /= rptr(ADRESS_WIDTH)) and
    (wptr(ADRESS_WIDTH - 1 downto 0) = rptr(ADRESS_WIDTH - 1 downto 0)) else
    '0';

end;
