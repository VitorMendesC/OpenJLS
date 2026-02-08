----------------------------------------------------------------------------------
-- Company:
-- Engineer:    Vitor Mendes Camilo
-- 
-- Create Date: 02/07/2026
-- Design Name: 
-- Module Name: A15_encode_run_segments - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:                 Code segment A.15
--                                      Encoding of run segments of length rg
--                                      Outputs the count of appended '1' bits
--
-- 
----------------------------------------------------------------------------------

use work.Common.all;

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity A15_encode_run_segments is
  generic (
    RUN_CNT_WIDTH   : natural := 16;
    RUN_INDEX_WIDTH : natural := 5
  );
  port (
    iRunCnt      : in unsigned (RUN_CNT_WIDTH - 1 downto 0);
    iRunIndex    : in unsigned (RUN_INDEX_WIDTH - 1 downto 0);
    oRunCnt      : out unsigned (RUN_CNT_WIDTH - 1 downto 0);
    oRunIndex    : out unsigned (RUN_INDEX_WIDTH - 1 downto 0);
    oAppendValid : out std_logic;
    oAppendCount : out unsigned (RUN_CNT_WIDTH - 1 downto 0)
  );
end A15_encode_run_segments;

architecture Behavioral of A15_encode_run_segments is

  type j_table_array is array (0 to 31) of natural;
  constant J_TABLE : j_table_array := (
  0, 0, 0, 0,
  1, 1, 1, 1,
  2, 2, 2, 2,
  3, 3, 3, 3,
  4, 4, 5, 5,
  6, 6, 7, 7,
  8, 9, 10, 11,
  12, 13, 14, 15
  );

  constant J_TABLE_SIZE : natural := J_TABLE'length;

begin

  process (iRunCnt, iRunIndex)
    variable vRunCnt      : unsigned (RUN_CNT_WIDTH - 1 downto 0);
    variable vJ           : natural;
    variable vRg          : unsigned (RUN_CNT_WIDTH - 1 downto 0);
    variable vRunIndexInt : integer;
    variable vAppendCnt   : unsigned (RUN_CNT_WIDTH - 1 downto 0);
    variable vDoAppend    : std_logic;
  begin

    vRunCnt      := iRunCnt;
    vRunIndexInt := to_integer(iRunIndex);
    vAppendCnt   := (others => '0');
    vDoAppend    := '0';

    for i in 0 to J_TABLE_SIZE - 1 loop
      vJ  := J_TABLE(vRunIndexInt);
      vRg := shift_left(to_unsigned(1, vRg'length), vJ);
      if vRunCnt >= vRg then
        vDoAppend  := '1';
        vRunCnt    := vRunCnt - vRg;
        vAppendCnt := vAppendCnt + 1;
        if vRunIndexInt < 31 then
          vRunIndexInt := vRunIndexInt + 1;
        end if;
      else
        exit;
      end if;
    end loop;

    -- NOTE: It is technically possible for the loop to exit before meeting the condition on the segment's while loop `while(RUNcnt >= (1 << J[RUNindex])) append '1'`, if this happens we won't comply with the standard
    -- TODO: Mathematically check if this condition can occur with the project parameters; Needs mathematical proof for bounds on the `for loop` to match the standard `while`;
    vJ  := J_TABLE(vRunIndexInt);
    vRg := shift_left(to_unsigned(1, vRg'length), vJ);
    assert not (vRunCnt >= vRg)
    report "A15: append count saturated; iterate externally or increase loop bound."
      severity warning;

    oRunCnt      <= vRunCnt;
    oRunIndex    <= to_unsigned(vRunIndexInt, oRunIndex'length);
    oAppendCount <= vAppendCnt;
    oAppendValid <= '1' when vDoAppend = '1' else
      '0';
  end process;

end Behavioral;
