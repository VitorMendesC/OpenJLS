----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 01/15/2026 10:04:39 PM
-- Design Name: 
-- Module Name: context_ram - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description:     Implements context RAM with data feed-forward
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

library openlogic_base;
use openlogic_base.olo_base_pkg_math.all;

entity context_ram is
  generic (
    RAM_DEPTH  : positive := 1024;
    WORD_WIDTH : positive := 32
  );

  port (
    iClk    : in std_logic;
    iWrAddr : in std_logic_vector(log2ceil(RAM_DEPTH) - 1 downto 0);
    iWrEn   : in std_logic;
    iWrData : in std_logic_vector(WORD_WIDTH - 1 downto 0);
    iRdAddr : in std_logic_vector(log2ceil(RAM_DEPTH) - 1 downto 0);
    iRdEn   : in std_logic;
    oRdData : out std_logic_vector(WORD_WIDTH - 1 downto 0)
  );
end context_ram;

architecture Behavioral of context_ram is
  signal sRamRdData : std_logic_vector(WORD_WIDTH - 1 downto 0);

begin

  olo_base_ram_sdp_inst : entity openlogic_base.olo_base_ram_sdp
    generic map(
      Depth_g         => RAM_DEPTH,
      Width_g         => WORD_WIDTH,
      IsAsync_g       => false,
      RdLatency_g     => 1,
      RamStyle_g      => "auto",
      RamBehavior_g   => "WBR",
      UseByteEnable_g => false,
      InitString_g    => "",
      InitFormat_g    => "NONE"
    )
    port map
    (
      Clk     => iClk,
      Wr_Addr => iWrAddr,
      Wr_Ena  => iWrEn,
      Wr_Be   => open,
      Wr_Data => iWrData,
      Rd_Clk  => open,
      Rd_Addr => iRdAddr,
      Rd_Ena  => iRdEn,
      Rd_Data => sRamRdData
    );

  oRdData <= iWrData when ((iWrEn and iRdEn) = '1' and iWrAddr = iRdAddr) else
    sRamRdData;

end Behavioral;
