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
use IEEE.NUMERIC_STD.all;

library openlogic_base;
use openlogic_base.olo_base_pkg_math.all;

use work.Common.all;

entity context_ram is
  generic (
    RANGE_P      : positive := CO_RANGE_STD;
    RAM_DEPTH   : positive := 367;
    A_WIDTH     : positive := CO_AQ_WIDTH_STD;
    B_WIDTH     : positive := CO_BQ_WIDTH_STD;
    C_WIDTH     : positive := CO_CQ_WIDTH;
    N_WIDTH     : positive := CO_NQ_WIDTH_STD;
    NN_WIDTH    : positive := CO_NNQ_WIDTH_STD;
    TOTAL_WIDTH : positive := CO_TOTAL_WIDTH_STD
  );

  port (
    iClk    : in std_logic;
    iRst    : in std_logic;
    iWrAddr : in std_logic_vector(log2ceil(RAM_DEPTH) - 1 downto 0);
    iWrEn   : in std_logic;
    iWrData : in std_logic_vector(TOTAL_WIDTH - 1 downto 0);
    iRdAddr : in std_logic_vector(log2ceil(RAM_DEPTH) - 1 downto 0);
    iRdEn   : in std_logic;
    oRdData : out std_logic_vector(TOTAL_WIDTH - 1 downto 0)
  );
end context_ram;

architecture Behavioral of context_ram is

  constant A_INIT : natural := math_max(2, (RANGE_P + 32) / 64);
  constant B_INIT : integer := 0;
  constant C_INIT : integer := 0;
  constant N_INIT : natural := 1;

  -- Packed init word (A | B | C | N)
  -- For run context (A | Nn | 0 | N)
  -- Nn also initializes to 0, like B
  constant CTX_INIT : std_logic_vector(TOTAL_WIDTH - 1 downto 0) :=
  std_logic_vector(to_unsigned(A_INIT, A_WIDTH)) &
  std_logic_vector(to_signed(B_INIT, B_WIDTH)) &
  std_logic_vector(to_signed(C_INIT, C_WIDTH)) &
  std_logic_vector(to_unsigned(N_INIT, N_WIDTH));

  signal sUseInitValue : std_logic_vector(RAM_DEPTH - 1 downto 0) := (others => '1'); -- Indicates if init value should be used for each address
  signal sUseInitReg   : std_logic                                := '0'; -- Registered flag aligning with BRAM RdLatency=1.
  signal sBramRdData   : std_logic_vector(TOTAL_WIDTH - 1 downto 0);

begin

  olo_base_ram_sdp_inst : entity openlogic_base.olo_base_ram_sdp
    generic map(
      Depth_g         => RAM_DEPTH,
      Width_g         => TOTAL_WIDTH,
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
      Rd_Data => sBramRdData
    );

  process (iClk)
  begin
    if rising_edge(iClk) then
      sUseInitReg <= sUseInitValue(to_integer(unsigned(iRdAddr)));

      if iRst = '1' then
        sUseInitValue <= (others => '1');
      elsif iRdEn = '1' then
        sUseInitValue(to_integer(unsigned(iRdAddr))) <= '0';
      end if;
    end if;
  end process;

  oRdData <= CTX_INIT when sUseInitReg = '1' else
    sBramRdData;

end Behavioral;
