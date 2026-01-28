----------------------------------------------------------------------------------
-- Company:
-- Engineer:    Vitor Mendes Camilo
-- 
-- Create Date: 08/18/2025 10:55:58 PM
-- Design Name: 
-- Module Name: quantization_gradients - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description:                             
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:                     Code segment A.4
--                                          Quantization of the gradients
--                      
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use Work.Common.all;

entity A4_quantization_gradients is
  generic (
    BITNESS : natural range 8 to 16 := CO_BITNESS_STD;
    MAX_VAL : natural               := CO_MAX_VAL_STD;
    NEAR    : natural               := CO_NEAR_STD
  );
  port (
    iD1 : in signed (BITNESS downto 0);
    iD2 : in signed (BITNESS downto 0);
    iD3 : in signed (BITNESS downto 0);
    oQ1 : out signed (3 downto 0);
    oQ2 : out signed (3 downto 0);
    oQ3 : out signed (3 downto 0)
  );
end A4_quantization_gradients;

architecture Behavioral of A4_quantization_gradients is

  function clamp (
    i        : integer;
    j        : integer;
    MaxValue : integer) return integer is
  begin
    if i > MaxValue or i < j then
      return j;
    else
      return i;
    end if;
  end function;

  -- NOTE: This computation has symmetry, it can de improved for performance
  function quantizate (
    signal Di   : signed (BITNESS downto 0);
    constant T1 : natural;
    constant T2 : natural;
    constant T3 : natural
  ) return signed is
    variable Qi : signed (3 downto 0);
  begin
    if (Di <= - T3) then
      Qi := to_signed(-4, Qi'length);
    elsif (Di <= - T2) then
      Qi := to_signed(-3, Qi'length);
    elsif (Di <= - T1) then
      Qi := to_signed(-2, Qi'length);
    elsif (Di <- NEAR) then
      Qi := to_signed(-1, Qi'length);
    elsif (Di <= NEAR) then
      Qi := to_signed(0, Qi'length);
    elsif (Di < T1) then
      Qi := to_signed(1, Qi'length);
    elsif (Di < T2) then
      Qi := to_signed(2, Qi'length);
    elsif (Di < T3) then
      Qi := to_signed(3, Qi'length);
    else
      Qi := to_signed(4, Qi'length);
    end if;

    return Qi;
  end function;

  constant BASIC_T1 : natural := 3;
  constant BASIC_T2 : natural := 7;
  constant BASIC_T3 : natural := 21;
  constant FACTOR   : natural := (minimum(MAX_VAL, 4095) + 128) / 256;
  constant T1       : natural := clamp(FACTOR * (BASIC_T1 - 2) + 2 + 3 * NEAR, NEAR + 1, MAX_VAL);
  constant T2       : natural := clamp(FACTOR * (BASIC_T2 - 3) + 3 + 5 * NEAR, T1, MAX_VAL);
  constant T3       : natural := clamp(FACTOR * (BASIC_T3 - 4) + 4 + 7 * NEAR, T2, MAX_VAL);

begin

  oQ1 <= quantizate(iD1, T1, T2, T3);
  oQ2 <= quantizate(iD2, T1, T2, T3);
  oQ3 <= quantizate(iD3, T1, T2, T3);

end Behavioral;
