----------------------------------------------------------------------------------
-- Company:
-- Engineer:    Vitor Mendes Camilo
-- 
-- Create Date: 09/03/2025 09:17:21 AM
-- Design Name: 
-- Module Name: context_ram - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
--                          Registered outputs, LUTRAM handles collision, 
--                          stalling isn't an potion, do it the right way
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
use IEEE.NUMERIC_STD.all;
use work.Common.all;

entity context_ram is
  generic (
    WORD_WIDTH    : natural                                    := 16;
    DEPTH         : natural                                    := 367;
    INITIAL_VALUE : std_logic_vector (WORD_WIDTH - 1 downto 0) := (others => '0')
  );
  port (
    iClk     : in std_logic;
    iRst     : in std_logic;
    iValidRd : in std_logic;
    iValidWr : in std_logic;
    iWrEn    : in std_logic;
    iQWrite  : in unsigned (clog2(DEPTH) - 1 downto 0); -- Q write
    iQRead   : in unsigned (clog2(DEPTH) - 1 downto 0); -- Q read
    iData    : in std_logic_vector (WORD_WIDTH - 1 downto 0);
    oData    : out std_logic_vector (WORD_WIDTH - 1 downto 0)
  );
end context_ram;

architecture Behavioral of context_ram is

  -- Memory signals
  signal sWrEn       : std_logic;
  signal sWrAddr     : unsigned (clog2(DEPTH) - 1 downto 0);
  signal sRdAddr     : unsigned (clog2(DEPTH) - 1 downto 0);
  signal sMemInData  : std_logic_vector (WORD_WIDTH - 1 downto 0);
  signal sMemOutData : std_logic_vector (WORD_WIDTH - 1 downto 0);

  -- General signals
  signal sUseInitValue : std_logic_vector (DEPTH - 1 downto 0) := (others => '1');

begin

  lutram_sdp_inst : entity work.lutram_sdp
    generic map(
      WIDTH      => WORD_WIDTH,
      DEPTH      => DEPTH,
      ADDR_WIDTH => clog2(WORD_WIDTH)
    )
    port map
    (
      iClk    => iClk,
      iWrEn   => sWrEn,
      iWrAddr => sWrAddr,
      iData   => sMemInData,
      iRdAddr => sRdAddr,
      oData   => sMemOutData
    );

  oData <= sMemOutData when sUseInitValue(to_integer(sRdAddr)) = '0' else
    INITIAL_VALUE;

  process (iClk)
  begin

    if rising_edge(iClk) then
      if iRst = '1' then
        sUseInitValue <= (others => '1');
      end if;
      if iValidRd = '1' then
        sUseInitValue(to_integer(sRdAddr)) <= '0';
      end if;

    end if;
  end process;
end Behavioral;
