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
--                          TODO: everything here needs to be thoroughly checked
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

  -- Functions
  function math_min(a, b      : in natural) return natural;
  function math_min(a, b      : in unsigned) return unsigned;
  function math_max(a, b      : in natural) return natural;
  function math_max(a, b      : in unsigned) return unsigned;
  function math_ceil_div(a, b : in natural) return natural; -- ceil(a / b)
  function std_to_int(s       : in std_logic) return integer;
  function bool2bit(b         : in boolean) return std_logic;

  -- Project's standard reference values ----------------------------------------------
  constant CO_BITNESS_STD           : natural := 12;
  constant CO_NEAR_STD              : natural := 0;
  constant CO_BYTE_STUFFER_IN_WIDTH : natural := 24; -- Bit packer output / byte stuffer input (3 bytes)
  constant CO_OUT_WIDTH_STD         : natural := 72; -- Final IP AXI-Stream output word width
  constant CO_BUFFER_WIDTH_STD      : natural := 96; -- Bit packer internal buffer width

  -- Defined values from T.87 ----------------------------------------------------------
  constant CO_BITNESS_MAX_WIDTH          : natural := 16;
  constant CO_MAX_VAL_STD                : natural := 2 ** CO_BITNESS_STD - 1;
  constant CO_ERROR_VALUE_WIDTH_STD      : natural := CO_BITNESS_STD + 1;
  constant CO_MAPPED_ERROR_VAL_WIDTH_STD : natural := CO_BITNESS_STD + 2;
  constant CO_CQ_WIDTH                   : natural := 8;
  -- Initialization
  constant CO_RANGE_STD : natural := CO_MAX_VAL_STD + 1;
  constant CO_QBPP_STD  : natural := log2(CO_RANGE_STD);                         -- number of bits to represent RANGE (ceil(log2(RANGE)))
  constant CO_BPP_STD   : natural := math_max(2, log2ceil(CO_MAX_VAL_STD + 1));  -- number of bits per pixel (ceil(log2(MAXVAL + 1)))
  constant CO_LIMIT_STD : natural := 2 * (CO_BPP_STD + math_max(8, CO_BPP_STD)); -- math_max length of the limited Golomb code

  type j_table_array is array (0 to 31) of natural;
  constant CO_J_TABLE : j_table_array := (
  0, 0, 0, 0,
  1, 1, 1, 1,
  2, 2, 2, 2,
  3, 3, 3, 3,
  4, 4, 5, 5,
  6, 6, 7, 7,
  8, 9, 10, 11,
  12, 13, 14, 15
  );

  constant CO_J_TABLE_SIZE : natural := CO_J_TABLE'length;

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
  constant CO_AQ_WIDTH_STD        : natural := CO_BITNESS_MAX_WIDTH * 2;
  constant CO_BQ_WIDTH_STD        : natural := CO_BITNESS_MAX_WIDTH * 2;
  constant CO_K_WIDTH_STD         : natural := log2ceil(CO_AQ_WIDTH_STD) + 1;
  constant CO_NQ_WIDTH_STD        : natural := log2ceil(CO_RESET_STD) + 1; -- Counts up to RESET
  constant CO_NNQ_WIDTH_STD       : natural := log2ceil(CO_RESET_STD) + 1; -- Counts up to RESET
  constant CO_TOTAL_WIDTH_STD     : natural := CO_AQ_WIDTH_STD + CO_BQ_WIDTH_STD + CO_CQ_WIDTH + CO_NQ_WIDTH_STD;

  -- Pipeline token record -------------------------------------------------------
  --
  -- Fields that cross an inter-stage register boundary. Intermediate
  -- combinational wires (gradients, mapped errval, Golomb code, Rx, Px)
  -- are local to their stage and are NOT in the record.
  --
  -- Mode tag:
  --   TOKEN_NONE             : pipeline bubble — downstream stages are NOPs
  --   TOKEN_REGULAR          : regular-mode sample (Golomb only)
  --   TOKEN_RUN_INTERRUPTION : run break (Golomb + A.16 raw prefix)
  --   TOKEN_RAW              : mid-run boundary emit (raw only)
  --
  -- Raw/Golomb bit-packer enables are derived from `mode` at Stage 5:
  --   raw    = (mode = TOKEN_RUN_INTERRUPTION or mode = TOKEN_RAW)
  --   Golomb = (mode = TOKEN_RUN_INTERRUPTION or mode = TOKEN_REGULAR)
  -- ---------------------------------------------------------------------------
  type t_token_mode is (TOKEN_NONE, TOKEN_REGULAR, TOKEN_RUN, TOKEN_RUN_INTERRUPTION, TOKEN_RAW);

  type t_pipeline_token is record
    mode : t_token_mode;
    -- Pixel values (Stage 1 → Stage 3)
    Ix : unsigned(CO_BITNESS_MAX_WIDTH - 1 downto 0);
    Ra : unsigned(CO_BITNESS_MAX_WIDTH - 1 downto 0);
    Rb : unsigned(CO_BITNESS_MAX_WIDTH - 1 downto 0);
    Rc : unsigned(CO_BITNESS_MAX_WIDTH - 1 downto 0);
    -- Context index + sign (Stage 2 → Stage 5)
    Q      : unsigned(8 downto 0);
    Sign   : std_logic;
    RItype : std_logic;
    -- Context variables (Stage 3 → Stage 5)
    Aq : unsigned(CO_AQ_WIDTH_STD - 1 downto 0);
    Bq : signed(CO_BQ_WIDTH_STD - 1 downto 0);
    Cq : signed(CO_CQ_WIDTH - 1 downto 0);
    Nq : unsigned(CO_NQ_WIDTH_STD - 1 downto 0);
    Nn : unsigned(CO_NQ_WIDTH_STD - 1 downto 0);
    -- RI TEMP (A.20 output → Stage 4 shared A.10). RI-only; unused in regular.
    Temp : unsigned(CO_AQ_WIDTH_STD - 1 downto 0);
    -- Error + k (Stage 3/4 → Stage 5)
    Errval : signed(CO_ERROR_VALUE_WIDTH_STD - 1 downto 0);
    k      : unsigned(CO_K_WIDTH_STD - 1 downto 0);
    -- Raw-bit fields (Stage 2 → Stage 5 bit packer)
    RawLen : unsigned(CO_SUFFIXLEN_WIDTH_STD - 1 downto 0);
    RawVal : unsigned(CO_SUFFIX_WIDTH_STD - 1 downto 0);
  end record;

  constant CO_TOKEN_NONE : t_pipeline_token := (
  mode   => TOKEN_NONE,
  Ix     => to_unsigned(0, CO_BITNESS_MAX_WIDTH),
  Ra     => to_unsigned(0, CO_BITNESS_MAX_WIDTH),
  Rb     => to_unsigned(0, CO_BITNESS_MAX_WIDTH),
  Rc     => to_unsigned(0, CO_BITNESS_MAX_WIDTH),
  Q      => to_unsigned(0, 9),
  Sign   => '0',
  RItype => '0',
  Aq     => to_unsigned(0, CO_AQ_WIDTH_STD),
  Bq     => to_signed(0, CO_BQ_WIDTH_STD),
  Cq     => to_signed(0, CO_CQ_WIDTH),
  Nq     => to_unsigned(0, CO_NQ_WIDTH_STD),
  Nn     => to_unsigned(0, CO_NQ_WIDTH_STD),
  Temp   => to_unsigned(0, CO_AQ_WIDTH_STD),
  Errval => to_signed(0, CO_ERROR_VALUE_WIDTH_STD),
  k      => to_unsigned(0, CO_K_WIDTH_STD),
  RawLen => to_unsigned(0, CO_SUFFIXLEN_WIDTH_STD),
  RawVal => to_unsigned(0, CO_SUFFIX_WIDTH_STD)
  );

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

  function math_ceil_div(a, b : in natural) return natural is
  begin
    return (a + b - 1) / b;
  end function;

  function std_to_int(s : in std_logic) return integer is
  begin
    -- Return 1 only for an explicit '1'; treat '0', 'U', 'X', 'Z', 'W', 'L',
    -- 'H', '-' as 0. Avoids spurious-1 during sim startup when a combinational
    -- path's source hasn't evaluated yet. Hardware has no 'U'.
    if s = '1' then
      return 1;
    else
      return 0;
    end if;
  end function;

  function bool2bit(b : in boolean) return std_logic is
  begin
    if b then
      return '1';
    else
      return '0';
    end if;
  end function;

end package body;