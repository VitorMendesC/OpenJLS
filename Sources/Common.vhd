----------------------------------------------------------------------------------
-- Company:
-- Engineer:    Vitor Mendes Camilo
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
--                          TODO: everything here needs to be throughly checked
-- 
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

library openlogic_base;
use openlogic_base.olo_base_pkg_math.log2ceil;
use openlogic_base.olo_base_pkg_math.log2;

package Common is

  -- Internal ----------------------------------------------------------------------------
  constant CO_SIGN_POS : std_logic := '0';
  constant CO_SIGN_NEG : std_logic := '1';

  function math_min(a, b : in natural) return natural;
  function math_min(a, b : in unsigned) return unsigned;
  function math_max(a, b : in natural) return natural;
  function math_max(a, b : in unsigned) return unsigned;

  -- Project's standard reference values ----------------------------------------------
  constant CO_BITNESS_STD      : natural := 12;
  constant CO_NEAR_STD         : natural := 0;
  constant CO_OUT_WIDTH_STD    : natural := 72; -- Output word width
  constant CO_BUFFER_WIDTH_STD : natural := 96; -- Output buffer width

  -- Defined values from T.87 ----------------------------------------------------------
  constant CO_BITNESS_MAX_WIDTH          : natural := 16;
  constant CO_MAX_VAL_STD                : natural := 2 ** CO_BITNESS_STD - 1;
  constant CO_ERROR_VALUE_WIDTH_STD      : natural := CO_BITNESS_STD + 1;
  constant CO_MAPPED_ERROR_VAL_WIDTH_STD : natural := CO_BITNESS_STD + 2;
  constant CO_CQ_WIDTH                   : natural := 8;
  -- Initialization
  constant CO_RANGE_STD : natural := CO_MAX_VAL_STD + 1;
  constant CO_QBPP_STD  : natural := log2(CO_RANGE_STD); -- number of bits to represent RANGE (ceil(log2(RANGE)))
  constant CO_BPP_STD   : natural := math_max(2, log2ceil(CO_MAX_VAL_STD + 1)); -- number of bits per pixel (ceil(log2(MAXVAL + 1)))
  constant CO_LIMIT_STD : natural := 2 * (CO_BPP_STD + math_max(8, CO_BPP_STD)); -- math_max length of the limited Golomb code

  -- Defined ranges from T.87 ---------------------------------------------------------- 
  constant CO_MAX_VAL_MAX_WIDTH : natural := 16;
  constant CO_RESET_MAX_WIDTH   : natural := 16;
  constant CO_MAX_CQ            : integer := 127;
  constant CO_MIN_CQ            : integer := - 128;
  constant CO_NEAR_MAX_STD      : natural := math_min(255, CO_MAX_VAL_STD/2);

  -- TODO: needs to be checked
  constant CO_RESET_STD : natural := 64;

  -- Unspecified by T.87
  -- TODO: needs to be checked
  constant CO_UNARY_WIDTH_STD     : natural := 16; -- enough to hold LIMIT - QBPP - 1
  constant CO_SUFFIX_WIDTH_STD    : natural := 16; -- max(qbpp, max_k)
  constant CO_SUFFIXLEN_WIDTH_STD : natural := 16; -- bits to encode suffix length (up to 31)
  constant CO_TOTLEN_WIDTH_STD    : natural := 16; -- bits to encode total length (up to LIMIT)
  constant CO_AQ_WIDTH_STD        : natural := CO_BITNESS_MAX_WIDTH * 2;
  constant CO_BQ_WIDTH_STD        : natural := CO_BITNESS_MAX_WIDTH * 2;
  constant CO_K_WIDTH_STD         : natural := log2ceil(CO_AQ_WIDTH_STD) + 1;
  constant CO_NQ_WIDTH_STD        : natural := log2ceil(CO_RESET_STD) + 1; -- Counts up to RESET

end package;

package body Common is

  function math_min(a, b : in natural) return natural is
  begin
    if a < b then
      return a;
    else
      return b;
    end if;
  end function;

  function math_min(a, b : in unsigned) return unsigned is
  begin
    if a < b then
      return a;
    else
      return b;
    end if;
  end function;

  function math_max(a, b : in unsigned) return unsigned is
  begin
    if a > b then
      return a;
    else
      return b;
    end if;
  end function;

  function math_max(a, b : in natural) return natural is
  begin
    if a > b then
      return a;
    else
      return b;
    end if;
  end function;

end package body;