use work.Common.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.env.all;

entity tb_A11_1 is
end;

architecture bench of tb_A11_1 is
  shared variable err_count : natural := 0;

  procedure check(cond : boolean; msg : string) is
  begin
    if not cond then
      report msg severity error;
      err_count := err_count + 1;
    end if;
  end procedure;

  constant K_WIDTH                : natural := CO_K_WIDTH_STD;
  constant QBPP                   : natural := CO_QBPP_STD;
  constant LIMIT                  : natural := CO_LIMIT_STD;
  constant UNARY_WIDTH            : natural := CO_UNARY_WIDTH_STD;
  constant SUFFIX_WIDTH           : natural := CO_SUFFIX_WIDTH_STD;
  constant SUFFIXLEN_WIDTH        : natural := CO_SUFFIXLEN_WIDTH_STD;
  constant TOTLEN_WIDTH           : natural := CO_TOTLEN_WIDTH_STD;
  constant MAPPED_ERROR_VAL_WIDTH : natural := CO_MAPPED_ERROR_VAL_WIDTH_STD;
  constant THRESHOLD              : natural := LIMIT - QBPP - 1;

  signal iK              : unsigned(K_WIDTH - 1 downto 0) := (others => '0');
  signal iMappedErrorVal : unsigned(MAPPED_ERROR_VAL_WIDTH - 1 downto 0) := (others => '0');
  signal oUnaryZeros     : unsigned(UNARY_WIDTH - 1 downto 0);
  signal oSuffixLen      : unsigned(SUFFIXLEN_WIDTH - 1 downto 0);
  signal oSuffixVal      : unsigned(SUFFIX_WIDTH - 1 downto 0);
  signal oTotalLen       : unsigned(TOTLEN_WIDTH - 1 downto 0);
  signal oIsEscape       : std_logic;

  function pow2(n : natural) return natural is
    variable v : natural := 1;
  begin
    if n = 0 then
      return 1;
    end if;
    for i in 1 to n loop
      v := v * 2;
    end loop;
    return v;
  end function;

  function lfsr_next(s : unsigned(31 downto 0)) return unsigned is
    variable v   : unsigned(31 downto 0) := s;
    variable bit : std_logic;
  begin
    bit := v(31) xor v(21) xor v(1) xor v(0);
    v   := v(30 downto 0) & bit;
    return v;
  end function;

  procedure check_case(
    signal sK       : out unsigned;
    signal sMErr    : out unsigned;
    signal sUnary   : in unsigned;
    signal sSufLen  : in unsigned;
    signal sSufVal  : in unsigned;
    signal sTotLen  : in unsigned;
    signal sEscape  : in std_logic;
    k_val           : natural;
    merr_val        : natural
  ) is
    variable step        : natural;
    variable high_order  : natural;
    variable low_order   : natural;
    variable exp_unary   : natural;
    variable exp_suf_len : natural;
    variable exp_suf_val : natural;
    variable exp_tot_len : natural;
    variable exp_escape  : std_logic;
  begin
    sK    <= to_unsigned(k_val, sK'length);
    sMErr <= to_unsigned(merr_val, sMErr'length);
    wait for 1 ns;

    step       := pow2(k_val);
    high_order := merr_val / step;
    low_order  := merr_val mod step;

    if high_order < THRESHOLD then
      exp_unary   := high_order;
      exp_suf_len := k_val;
      exp_suf_val := low_order;
      exp_tot_len := high_order + 1 + k_val;
      exp_escape  := '0';
    else
      exp_unary   := THRESHOLD;
      exp_suf_len := QBPP;
      exp_suf_val := (merr_val - 1) mod pow2(QBPP);
      exp_tot_len := LIMIT;
      exp_escape  := '1';
    end if;

    check(sUnary = to_unsigned(exp_unary, sUnary'length),
      "A11.1 unary mismatch: k=" & integer'image(integer(k_val)) &
      " MErr=" & integer'image(integer(merr_val)) &
      " exp=" & integer'image(integer(exp_unary)) &
      " got=" & integer'image(to_integer(sUnary))
    );

    check(sSufLen = to_unsigned(exp_suf_len, sSufLen'length),
      "A11.1 suffix length mismatch: k=" & integer'image(integer(k_val)) &
      " MErr=" & integer'image(integer(merr_val)) &
      " exp=" & integer'image(integer(exp_suf_len)) &
      " got=" & integer'image(to_integer(sSufLen))
    );

    check(sSufVal = to_unsigned(exp_suf_val, sSufVal'length),
      "A11.1 suffix value mismatch: k=" & integer'image(integer(k_val)) &
      " MErr=" & integer'image(integer(merr_val)) &
      " exp=" & integer'image(integer(exp_suf_val)) &
      " got=" & integer'image(to_integer(sSufVal))
    );

    check(sTotLen = to_unsigned(exp_tot_len, sTotLen'length),
      "A11.1 total length mismatch: k=" & integer'image(integer(k_val)) &
      " MErr=" & integer'image(integer(merr_val)) &
      " exp=" & integer'image(integer(exp_tot_len)) &
      " got=" & integer'image(to_integer(sTotLen))
    );

    check(sEscape = exp_escape,
      "A11.1 escape mismatch: k=" & integer'image(integer(k_val)) &
      " MErr=" & integer'image(integer(merr_val)) &
      " exp=" & std_logic'image(exp_escape) &
      " got=" & std_logic'image(sEscape)
    );
  end procedure;
begin
  dut : entity work.A11_1_golomb_encoder
    generic map(
      K_WIDTH                => K_WIDTH,
      QBPP                   => QBPP,
      LIMIT                  => LIMIT,
      UNARY_WIDTH            => UNARY_WIDTH,
      SUFFIX_WIDTH           => SUFFIX_WIDTH,
      SUFFIXLEN_WIDTH        => SUFFIXLEN_WIDTH,
      TOTLEN_WIDTH           => TOTLEN_WIDTH,
      MAPPED_ERROR_VAL_WIDTH => MAPPED_ERROR_VAL_WIDTH
    )
    port map(
      iK              => iK,
      iMappedErrorVal => iMappedErrorVal,
      oUnaryZeros     => oUnaryZeros,
      oSuffixLen      => oSuffixLen,
      oSuffixVal      => oSuffixVal,
      oTotalLen       => oTotalLen,
      oIsEscape       => oIsEscape
    );

  stim : process
    variable lfsr   : unsigned(31 downto 0) := x"5C71A2E9";
    variable k_v    : natural;
    variable merr_v : natural;
  begin
    -- Directed cases
    check_case(iK, iMappedErrorVal, oUnaryZeros, oSuffixLen, oSuffixVal, oTotalLen, oIsEscape, 0, 0);
    check_case(iK, iMappedErrorVal, oUnaryZeros, oSuffixLen, oSuffixVal, oTotalLen, oIsEscape, 2, 9);
    check_case(iK, iMappedErrorVal, oUnaryZeros, oSuffixLen, oSuffixVal, oTotalLen, oIsEscape, 4, 63);
    check_case(iK, iMappedErrorVal, oUnaryZeros, oSuffixLen, oSuffixVal, oTotalLen, oIsEscape, 1, (THRESHOLD - 1) * 2 + 1);
    check_case(iK, iMappedErrorVal, oUnaryZeros, oSuffixLen, oSuffixVal, oTotalLen, oIsEscape, 1, THRESHOLD * 2);
    check_case(iK, iMappedErrorVal, oUnaryZeros, oSuffixLen, oSuffixVal, oTotalLen, oIsEscape, 0, THRESHOLD);
    check_case(iK, iMappedErrorVal, oUnaryZeros, oSuffixLen, oSuffixVal, oTotalLen, oIsEscape, QBPP, (2 ** MAPPED_ERROR_VAL_WIDTH) - 1);

    -- Pseudo-random coverage
    for i in 0 to 999 loop
      lfsr   := lfsr_next(lfsr);
      k_v    := to_integer(unsigned(lfsr(3 downto 0))) mod (QBPP + 1);
      lfsr   := lfsr_next(lfsr);
      merr_v := to_integer(unsigned(lfsr(MAPPED_ERROR_VAL_WIDTH - 1 downto 0)));

      check_case(iK, iMappedErrorVal, oUnaryZeros, oSuffixLen, oSuffixVal, oTotalLen, oIsEscape, k_v, merr_v);
    end loop;

    if err_count > 0 then
      report "tb_A11_1 RESULT: FAIL (" & integer'image(err_count) & " errors)" severity failure;
    else
      report "tb_A11_1 RESULT: PASS" severity note;
    end if;
    finish;
  end process;
end;
