----------------------------------------------------------------------------------
-- Company:
-- Engineer:    Vitor Mendes Camilo
-- 
-- Create Date: 09/02/2025 10:01:22 PM
-- Design Name: 
-- Module Name: memory - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description:           Generic memory, hopefully it gets mapped to BRAM

-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
--                        NOTE: Somewhat made by ChatGPT, test everything!
-- 
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.Common.all;

entity true_dual_port_ram is
  generic (
    WIDTH    : positive := 32;
    DEPTH    : positive := 1024;        -- >=512*WIDTH usually infers BRAM
    RDW_MODE : string   := "READ_FIRST" -- or "WRITE_FIRST"
  );
  port (
    -- Port A
    clka  : in std_logic;
    ena   : in std_logic := '1';
    wea   : in std_logic := '0';
    addra : in unsigned(integer(clog2(DEPTH)) - 1 downto 0);
    dina  : in std_logic_vector(WIDTH - 1 downto 0);
    douta : out std_logic_vector(WIDTH - 1 downto 0);

    -- Port B
    clkb  : in std_logic;
    enb   : in std_logic := '1';
    web   : in std_logic := '0';
    addrb : in unsigned(integer(clog2(DEPTH)) - 1 downto 0);
    dinb  : in std_logic_vector(WIDTH - 1 downto 0);
    doutb : out std_logic_vector(WIDTH - 1 downto 0)
  );
end entity;

architecture rtl of true_dual_port_ram is
  -- memory array
  type ram_t is array (0 to DEPTH - 1) of std_logic_vector(WIDTH - 1 downto 0);
  signal ram : ram_t := (others => (others => '0'));

  -- synthesis-friendly read muxes
  signal doa_r, dob_r : std_logic_vector(WIDTH - 1 downto 0);

begin
  -- Port A
  process (clka)
    variable rd_data_a : std_logic_vector(WIDTH - 1 downto 0);
    variable rd_data_b : std_logic_vector(WIDTH - 1 downto 0);
  begin
    if rising_edge(clka) then
      if ena = '1' then
        rd_data_a := ram(to_integer(addra));
        if wea = '1' then
          doa_r                  <= rd_data_a;
          ram(to_integer(addra)) <= dina;
        else
          doa_r <= rd_data_a;
        end if;
      end if;
    end if;

    if rising_edge(clkb) then
      if enb = '1' then
        rd_data_b := ram(to_integer(addrb));
        if web = '1' then
          dob_r                  <= rd_data_b;
          ram(to_integer(addrb)) <= dinb;
        else
          dob_r <= rd_data_b;
        end if;
      end if;
    end if;
  end process;

  douta <= doa_r;
  doutb <= dob_r;
end architecture;
