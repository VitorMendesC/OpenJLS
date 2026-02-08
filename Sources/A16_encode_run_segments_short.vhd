----------------------------------------------------------------------------------
-- Company:
-- Engineer:    Vitor Mendes Camilo
-- 
-- Create Date: 02/07/2026
-- Design Name: 
-- Module Name: A16_encode_run_segments_short - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:                 Code segment A.16
--                                      Encoding of run segments of length less than rg
-- 
----------------------------------------------------------------------------------

use work.Common.all;

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity A16_encode_run_segments_short is
  generic (
    BITNESS         : natural range 8 to 16 := CO_BITNESS_STD;
    RUN_CNT_WIDTH   : natural               := 16;
    RUN_INDEX_WIDTH : natural               := 5;
    J_WIDTH         : natural               := 5;
    NEAR            : natural               := CO_NEAR_STD
  );
  port (
    iIx          : in unsigned (BITNESS - 1 downto 0);
    iRunVal      : in unsigned (BITNESS - 1 downto 0);
    iRunCnt      : in unsigned (RUN_CNT_WIDTH - 1 downto 0);
    iRunIndex    : in unsigned (RUN_INDEX_WIDTH - 1 downto 0);
    oRunIndex    : out unsigned (RUN_INDEX_WIDTH - 1 downto 0);
    oAppendValid : out std_logic;
    oPrefixBit   : out std_logic;
    oRunCntVal   : out unsigned (RUN_CNT_WIDTH - 1 downto 0);
    oRunCntLen   : out unsigned (J_WIDTH - 1 downto 0)
  );
end A16_encode_run_segments_short;

architecture Behavioral of A16_encode_run_segments_short is
begin

  process (iIx, iRunVal, iRunCnt, iRunIndex)
    variable vRunIndexInt : integer;
    variable vJ           : natural;
    variable vRunIndex    : unsigned (RUN_INDEX_WIDTH - 1 downto 0);
    variable vAppend      : std_logic;
    variable vPrefix      : std_logic;
    variable vLen         : unsigned (J_WIDTH - 1 downto 0);
    variable vRunCnt      : unsigned (RUN_CNT_WIDTH - 1 downto 0);

  begin

    vRunIndexInt := to_integer(iRunIndex);
    vJ           := CO_J_TABLE(vRunIndexInt);
    vRunIndex    := iRunIndex;
    vAppend      := '0';
    vPrefix      := '0';
    vLen         := (others => '0');
    vRunCnt      := (others => '0');

    if abs(to_integer(iIx) - to_integer(iRunVal)) > NEAR then
      vAppend := '1';
      vPrefix := '0';
      vLen    := to_unsigned(vJ, vLen'length);
      vRunCnt := iRunCnt;
      if vRunIndexInt > 0 then
        vRunIndex := vRunIndex - 1;
      end if;
    elsif iRunCnt > 0 then
      vAppend := '1';
      vPrefix := '1';
      vLen    := (others => '0');
      vRunCnt := (others => '0');
    end if;

    oRunIndex    <= vRunIndex;
    oAppendValid <= vAppend;
    oPrefixBit   <= vPrefix;
    oRunCntLen   <= vLen;
    oRunCntVal   <= vRunCnt;
  end process;

end Behavioral;
