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

use work.common.all;

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library openlogic_base;
  use openlogic_base.olo_base_pkg_math.all;
  use std.env.all;

entity tb_context_ram is
end entity tb_context_ram;

architecture bench of tb_context_ram is

  shared variable errCount : natural;

  procedure check (
    cond : boolean;
    msg  : string
  ) is
  begin

    if (not cond) then
      report msg
        severity error;
      errCount := errCount + 1;
    end if;

  end procedure check;

  -- Clock period
  constant CLK_PERIOD      : time := 5 ns;
  constant CSTDWAIT        : time := 10 * CLK_PERIOD;

  -- Generics
  constant RAM_DEPTH       : positive := 1024;
  constant TOTAL_WIDTH     : positive := CO_TOTAL_WIDTH_STD;
  -- Ports
  signal iClk              : std_logic;
  signal iRst              : std_logic;
  signal iWrAddr           : std_logic_vector(log2ceil(RAM_DEPTH) - 1 downto 0);
  signal iWrEn             : std_logic;
  signal iWrData           : std_logic_vector(TOTAL_WIDTH - 1 downto 0);
  signal iRdAddr           : std_logic_vector(log2ceil(RAM_DEPTH) - 1 downto 0);
  signal iRdEn             : std_logic;
  signal iEndOfImage       : std_logic;
  signal oRdData           : std_logic_vector(TOTAL_WIDTH - 1 downto 0);

begin

  context_ram_inst : entity work.context_ram(behavioral)

    generic map (
      RAM_DEPTH   => RAM_DEPTH,
      TOTAL_WIDTH => TOTAL_WIDTH
    )
    port map (
      iClk        => iClk,
      iRst        => iRst,
      iWrAddr     => iWrAddr,
      iWrEn       => iWrEn,
      iWrData     => iWrData,
      iRdAddr     => iRdAddr,
      iRdEn       => iRdEn,
      iEndOfImage => iEndOfImage,
      oRdData     => oRdData
    );

  clk_proc : process is
  begin

    iClk <= '1';
    wait for CLK_PERIOD / 2;
    iClk <= '0';
    wait for CLK_PERIOD / 2;

  end process clk_proc;

  stim : process is
  begin

    -- Initial values (no defaults — set explicitly here)
    iRst        <= '1';
    iEndOfImage <= '0';
    iWrAddr     <= (others => '0');
    iWrEn       <= '0';
    iWrData     <= (others => '0');
    iRdAddr     <= (others => '0');
    iRdEn       <= '0';

    wait for CSTDWAIT;
    iRst <= '0';
    wait until rising_edge(iClk);

    -- Write a known value to addr 0
    iWrAddr <= (others => '0');
    iWrData <= std_logic_vector(to_unsigned(16#BEBEBEE#, TOTAL_WIDTH));
    iWrEn   <= '1';
    wait until rising_edge(iClk);
    iWrEn   <= '0';

    -- First read of addr 0 should return the init context (per-address first-read marker)
    iRdAddr <= (others => '0');
    iRdEn   <= '1';
    wait until rising_edge(iClk);
    iRdEn   <= '0';
    wait until rising_edge(iClk);
    -- One more delta to let combinational mux propagate
    wait for 1 ns;
    check(oRdData /= std_logic_vector(to_unsigned(16#BEBEBEE#, TOTAL_WIDTH)),
          "First read after write should return CTX_INIT, not stored data");

    -- Second read of addr 0 should return the previously written value
    iRdEn <= '1';
    wait until rising_edge(iClk);
    iRdEn <= '0';
    wait until rising_edge(iClk);
    wait for 1 ns;
    check(oRdData = std_logic_vector(to_unsigned(16#BEBEBEE#, TOTAL_WIDTH)),
          "Second read should return stored data");

    wait for CSTDWAIT;

    if (errCount > 0) then
      report "tb_context_ram RESULT: FAIL (" & integer'image(errCount) & " errors)"
        severity failure;
    else
      report "tb_context_ram RESULT: PASS"
        severity note;
    end if;

    finish;

  end process stim;

end architecture bench;
