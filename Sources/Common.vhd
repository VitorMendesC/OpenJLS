----------------------------------------------------------------------------------
-- Company:
-- Engineer:    Vitor Mendes Camilow
-- 
-- Create Date: 08/18/2025 09:44:52 PM
-- Design Name: 
-- Module Name: Common - Behavioral
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

package Common is

  constant CO_BITNESS : natural := 12;
  constant CO_A_WIDTH : natural := CO_BITNESS + 6;
  constant CO_B_WIDTH : natural := CO_BITNESS + 5;
  constant CO_C_WIDTH : natural := CO_BITNESS + 1;
  constant CO_N_WIDTH : natural := 7;
  constant CO_MAX_VAL : natural := 2 ** CO_BITNESS - 1;
  constant CO_RANGE   : natural := 2 ** CO_BITNESS;

  -- C[Q] parameters, signed value
  constant CO_MAX_CQ   : integer := 127;
  constant CO_MIN_CQ   : integer := - 128;
  constant CO_CQ_WIDTH : natural := 8;

  function minimum(a, b : in natural) return natural;
  function minimum(a, b : in unsigned) return unsigned;
  function maximum(a, b : in unsigned) return unsigned;

end package;

package body Common is

  function minimum(a, b : in natural) return natural is
  begin
    if a < b then
      return a;
    else
      return b;
    end if;
  end function;

  function minimum(a, b : in unsigned) return unsigned is
  begin
    if a < b then
      return a;
    else
      return b;
    end if;
  end function;

  function maximum(a, b : in unsigned) return unsigned is
  begin
    if a > b then
      return a;
    else
      return b;
    end if;
  end function;

end package body;