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

  constant CO_BITNESS_MAX_WIDTH : natural := 16;

  -- Unspecified by T.87
  constant CO_A_MAX_WIDTH : natural := CO_BITNESS_MAX_WIDTH * 2;
  constant CO_B_MAX_WIDTH : natural := CO_BITNESS_MAX_WIDTH * 2;
  constant CO_C_MAX_WIDTH : natural := CO_BITNESS_MAX_WIDTH * 2;

  -- MAXVAL
  constant CO_MAXVAL_MAX_WIDTH : natural := 16;

  -- RESET and N[Q]
  constant CO_RESET_MAX_WIDTH : natural := 16;
  constant CO_N_MAX_WIDTH     : natural := 16; -- Counts up to RESET

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