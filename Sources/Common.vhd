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
----------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library work;
  use work.olo_base_pkg_math.log2ceil;
  use work.olo_base_pkg_math.log2;

package common is

  -- Internal ----------------------------------------------------------------------------
  constant CO_SIGN_POS         : std_logic := '0';
  constant CO_SIGN_NEG         : std_logic := '1';
  constant CO_MIN_IMAGE_WIDTH  : natural   := 4;
  constant CO_MIN_IMAGE_HEIGHT : natural   := 1;

  -- Functions

  -- math_max/math_min over integers alias open-logic's max/min: an alias is
  -- usable in the package-declaration constants below (a local function body is
  -- not yet elaborated there — LRM 14.4.2), and gives `min` a name that doesn't
  -- clash with the predefined TIME unit.
  alias math_max is work.olo_base_pkg_math.max [integer, integer return integer];
  alias math_min is work.olo_base_pkg_math.min [integer, integer return integer];

  -- unsigned overloads (olo has none); used only at run time in architectures.
  function math_min (
    a,
    b      : in unsigned
  ) return unsigned;

  function math_max (
    a,
    b      : in unsigned
  ) return unsigned;

  function math_ceil_div (
    a,
    b : in natural
  ) return natural; -- ceil(a / b)

  function std_to_int (
    s       : in std_logic
  ) return integer;

  function bool2bit (
    b         : in boolean
  ) return std_logic;

  -- Project's standard reference values ----------------------------------------------
  constant CO_BITNESS_STD   : natural := 12;
  constant CO_NEAR_STD      : natural := 0;
  constant CO_OUT_WIDTH_STD : natural := 64;

  -- Defined values from T.87 ----------------------------------------------------------
  constant CO_BITNESS_MAX_WIDTH          : natural := 16;
  constant CO_MAX_VAL_STD                : natural := 2 ** CO_BITNESS_STD - 1;
  constant CO_ERROR_VALUE_WIDTH_STD      : natural := CO_BITNESS_STD + 1;
  constant CO_MAPPED_ERROR_VAL_WIDTH_STD : natural := CO_BITNESS_STD + 2;
  constant CO_CQ_WIDTH                   : natural := 8;
  -- Initialization
  constant CO_RANGE_STD : natural := CO_MAX_VAL_STD + 1;
  constant CO_QBPP_STD  : natural := log2ceil(CO_RANGE_STD);                     -- number of bits to represent RANGE (ceil(log2(RANGE)))
  constant CO_BPP_STD   : natural := math_max(2, log2ceil(CO_MAX_VAL_STD + 1));  -- number of bits per pixel (ceil(log2(MAXVAL + 1)))
  constant CO_LIMIT_STD : natural := 2 * (CO_BPP_STD + math_max(8, CO_BPP_STD)); -- max length of the limited Golomb code

  type j_table_array is array (0 to 31) of natural;

  constant CO_J_TABLE : j_table_array :=
  (
    0,
    0,
    0,
    0,
    1,
    1,
    1,
    1,
    2,
    2,
    2,
    2,
    3,
    3,
    3,
    3,
    4,
    4,
    5,
    5,
    6,
    6,
    7,
    7,
    8,
    9,
    10,
    11,
    12,
    13,
    14,
    15
  );

  constant CO_J_TABLE_SIZE : natural := CO_J_TABLE'length;

  -- Defined ranges from T.87 ----------------------------------------------------------
  constant CO_MAX_VAL_MAX_WIDTH : natural := 16;
  constant CO_RESET_MAX_WIDTH   : natural := 16;
  constant CO_MAX_CQ            : integer := 127;
  constant CO_MIN_CQ            : integer := - 128;
  constant CO_NEAR_MAX_STD      : natural := math_min(255, CO_MAX_VAL_STD / 2);

  constant CO_RESET_STD : natural := 64;                                        -- T.87 default RESET

  -- Unspecified by T.87. Widths mirror openjls_top's T.87 / Murat-2018 derivation
  -- (pipeline arithmetic widths) for the standard reference config.
  constant CO_AQ_WIDTH_STD        : natural := CO_BPP_STD + log2ceil(CO_RESET_STD);            -- A < RESET*2^(bpp-1), +1 sum headroom
  constant CO_BQ_WIDTH_STD        : natural := CO_BPP_STD + 1;                                 -- B signed, holds B+Errval
  constant CO_K_WIDTH_STD         : natural := log2ceil(CO_AQ_WIDTH_STD + 1);                  -- holds k in [0, MAX_K = A_WIDTH]
  constant CO_NQ_WIDTH_STD        : natural := log2ceil(CO_RESET_STD + 1);                     -- N counts up to RESET
  constant CO_NNQ_WIDTH_STD       : natural := log2ceil(CO_RESET_STD);                         -- Nn counts up to RESET
  constant CO_UNARY_WIDTH_STD     : natural := log2ceil(CO_LIMIT_STD - CO_QBPP_STD);           -- regular quotient / escape threshold (LIMIT-QBPP-1)
  constant CO_SUFFIX_WIDTH_STD    : natural := CO_AQ_WIDTH_STD;                                -- regular k bits / escape QBPP, both <= MAX_K (= A_WIDTH)
  constant CO_SUFFIXLEN_WIDTH_STD : natural := math_max(CO_K_WIDTH_STD, log2ceil(15 + 2));     -- T.87 J max = 15
  constant CO_TOTAL_WIDTH_STD     : natural := CO_AQ_WIDTH_STD + CO_BQ_WIDTH_STD + CO_CQ_WIDTH + CO_NQ_WIDTH_STD;

  -- Bit-packer / byte-stuffer / framer interface widths -------------------------
  constant CO_BIT_PACKER_OUT_WIDTH             : natural := CO_LIMIT_STD;
  constant CO_BYTE_STUFFER_OUT_BYTES_PER_CYCLE : natural := 4;
  constant CO_BYTE_STUFFER_OUT_WIDTH           : natural := CO_BYTE_STUFFER_OUT_BYTES_PER_CYCLE * 8;
  constant CO_BYTE_STUFFER_BURST_DEPTH         : natural := 16;

end package common;

package body common is

  function math_min (
    a,
    b : in unsigned
  ) return unsigned is
  begin

    if (a < b) then
      return a;
    else
      return b;
    end if;

  end function math_min;

  function math_max (
    a,
    b : in unsigned
  ) return unsigned is
  begin

    if (a > b) then
      return a;
    else
      return b;
    end if;

  end function math_max;

  function math_ceil_div (
    a,
    b : in natural
  ) return natural is
  begin

    return (a + b - 1) / b;

  end function math_ceil_div;

  function std_to_int (
    s : in std_logic
  ) return integer is
  begin

    -- Return 1 only for an explicit '1'; treat '0', 'U', 'X', 'Z', 'W', 'L',
    -- 'H', '-' as 0. Avoids spurious-1 during sim startup when a combinational
    -- path's source hasn't evaluated yet. Hardware has no 'U'.
    if (s = '1') then
      return 1;
    else
      return 0;
    end if;

  end function std_to_int;

  function bool2bit (
    b : in boolean
  ) return std_logic is
  begin

    if (b) then
      return '1';
    else
      return '0';
    end if;

  end function bool2bit;

end package body common;
