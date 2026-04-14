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
  constant CO_QBPP_STD  : natural := log2(CO_RANGE_STD); -- number of bits to represent RANGE (ceil(log2(RANGE)))
  constant CO_BPP_STD   : natural := math_max(2, log2ceil(CO_MAX_VAL_STD + 1)); -- number of bits per pixel (ceil(log2(MAXVAL + 1)))
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
  constant CO_TOTLEN_WIDTH_STD    : natural := 16; -- bits to encode total length (up to LIMIT)
  constant CO_AQ_WIDTH_STD        : natural := CO_BITNESS_MAX_WIDTH * 2;
  constant CO_BQ_WIDTH_STD        : natural := CO_BITNESS_MAX_WIDTH * 2;
  constant CO_K_WIDTH_STD         : natural := log2ceil(CO_AQ_WIDTH_STD) + 1;
  constant CO_NQ_WIDTH_STD        : natural := log2ceil(CO_RESET_STD) + 1; -- Counts up to RESET

  -- Pipeline token record -------------------------------------------------------
  --
  -- A single record that flows through all pipeline stages, modelling the
  -- inter-stage register. Each stage populates its fields and passes
  -- everything downstream; synthesis trims unused registers automatically.
  --
  -- Mode tag:
  --   TOKEN_NONE             : pipeline bubble — downstream stages are NOPs
  --   TOKEN_REGULAR          : regular-mode sample
  --   TOKEN_RUN_INTERRUPTION : run-interruption break
  --   TOKEN_RAW              : raw bit append (A.15 boundary '1's)
  --
  -- All pixel-width fields use CO_BITNESS_MAX_WIDTH so the record is
  -- valid for any supported bitness; stages resize when driving ports.
  -- ---------------------------------------------------------------------------
  type t_token_mode is (TOKEN_NONE, TOKEN_REGULAR, TOKEN_RUN_INTERRUPTION, TOKEN_RAW);

  type t_pipeline_token is record

    mode : t_token_mode;

    -- Pixel values (Input stage → consumed through Stage 3) -----------------
    Ix : unsigned(CO_BITNESS_MAX_WIDTH - 1 downto 0);
    Ra : unsigned(CO_BITNESS_MAX_WIDTH - 1 downto 0);
    Rb : unsigned(CO_BITNESS_MAX_WIDTH - 1 downto 0);
    Rc : unsigned(CO_BITNESS_MAX_WIDTH - 1 downto 0);
    Rd : unsigned(CO_BITNESS_MAX_WIDTH - 1 downto 0);

    -- Gradients (Stage 1 → consumed by Stage 2) ----------------------------
    D1 : signed(CO_BITNESS_MAX_WIDTH downto 0);
    D2 : signed(CO_BITNESS_MAX_WIDTH downto 0);
    D3 : signed(CO_BITNESS_MAX_WIDTH downto 0);

    -- Context (Stage 2 →) --------------------------------------------------
    Q    : unsigned(8 downto 0);  -- context index 0..366
    Sign : std_logic;             -- from A.4.1 (regular) or A.19 (run)

    -- Context variables (memory read + forwarding mux, Stage 2/3 →) --------
    Aq : unsigned(CO_AQ_WIDTH_STD - 1 downto 0);
    Bq : signed(CO_BQ_WIDTH_STD - 1 downto 0);
    Cq : signed(CO_CQ_WIDTH - 1 downto 0);
    Nq : unsigned(CO_NQ_WIDTH_STD - 1 downto 0);
    Nn : unsigned(CO_NQ_WIDTH_STD - 1 downto 0);

    -- Prediction (Stage 3 →) -----------------------------------------------
    Px     : unsigned(CO_BITNESS_MAX_WIDTH - 1 downto 0);
    Errval : signed(CO_ERROR_VALUE_WIDTH_STD - 1 downto 0);
    Rx     : unsigned(CO_BITNESS_MAX_WIDTH - 1 downto 0);  -- reconstructed value

    -- Error encoding (Stage 4 →) -------------------------------------------
    k       : unsigned(CO_K_WIDTH_STD - 1 downto 0);
    MErrval : unsigned(CO_MAPPED_ERROR_VAL_WIDTH_STD - 1 downto 0);

    -- Run mode (Stage 2/3 →) -----------------------------------------------
    RUNindex : unsigned(4 downto 0);
    RItype   : std_logic;

    -- Golomb code (output stages) -------------------------------------------
    UnaryZeros : unsigned(CO_UNARY_WIDTH_STD - 1 downto 0);
    SuffixLen  : unsigned(CO_SUFFIXLEN_WIDTH_STD - 1 downto 0);
    SuffixVal  : unsigned(CO_SUFFIX_WIDTH_STD - 1 downto 0);
    TotalLen   : unsigned(CO_TOTLEN_WIDTH_STD - 1 downto 0);
    IsEscape   : std_logic;

    -- Raw bit fields (run encoding / RI prefix) -----------------------------
    RawSuffixLen : unsigned(CO_SUFFIXLEN_WIDTH_STD - 1 downto 0);
    RawSuffixVal : unsigned(CO_SUFFIX_WIDTH_STD - 1 downto 0);
    HasRawPrefix : std_logic;
    PrefixLen    : unsigned(CO_SUFFIXLEN_WIDTH_STD - 1 downto 0);
    PrefixVal    : unsigned(CO_SUFFIX_WIDTH_STD - 1 downto 0);

  end record;

  constant CO_TOKEN_NONE : t_pipeline_token := (
    mode         => TOKEN_NONE,
    Ix           => to_unsigned(0, CO_BITNESS_MAX_WIDTH),
    Ra           => to_unsigned(0, CO_BITNESS_MAX_WIDTH),
    Rb           => to_unsigned(0, CO_BITNESS_MAX_WIDTH),
    Rc           => to_unsigned(0, CO_BITNESS_MAX_WIDTH),
    Rd           => to_unsigned(0, CO_BITNESS_MAX_WIDTH),
    D1           => to_signed(0, CO_BITNESS_MAX_WIDTH + 1),
    D2           => to_signed(0, CO_BITNESS_MAX_WIDTH + 1),
    D3           => to_signed(0, CO_BITNESS_MAX_WIDTH + 1),
    Q            => to_unsigned(0, 9),
    Sign         => '0',
    Aq           => to_unsigned(0, CO_AQ_WIDTH_STD),
    Bq           => to_signed(0, CO_BQ_WIDTH_STD),
    Cq           => to_signed(0, CO_CQ_WIDTH),
    Nq           => to_unsigned(0, CO_NQ_WIDTH_STD),
    Nn           => to_unsigned(0, CO_NQ_WIDTH_STD),
    Px           => to_unsigned(0, CO_BITNESS_MAX_WIDTH),
    Errval       => to_signed(0, CO_ERROR_VALUE_WIDTH_STD),
    Rx           => to_unsigned(0, CO_BITNESS_MAX_WIDTH),
    k            => to_unsigned(0, CO_K_WIDTH_STD),
    MErrval      => to_unsigned(0, CO_MAPPED_ERROR_VAL_WIDTH_STD),
    RUNindex     => to_unsigned(0, 5),
    RItype       => '0',
    UnaryZeros   => to_unsigned(0, CO_UNARY_WIDTH_STD),
    SuffixLen    => to_unsigned(0, CO_SUFFIXLEN_WIDTH_STD),
    SuffixVal    => to_unsigned(0, CO_SUFFIX_WIDTH_STD),
    TotalLen     => to_unsigned(0, CO_TOTLEN_WIDTH_STD),
    IsEscape     => '0',
    RawSuffixLen => to_unsigned(0, CO_SUFFIXLEN_WIDTH_STD),
    RawSuffixVal => to_unsigned(0, CO_SUFFIX_WIDTH_STD),
    HasRawPrefix => '0',
    PrefixLen    => to_unsigned(0, CO_SUFFIXLEN_WIDTH_STD),
    PrefixVal    => to_unsigned(0, CO_SUFFIX_WIDTH_STD)
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
    if s = '0' then
      return 0;
    else
      return 1;
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