use work.common.all;

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use std.env.all;

entity tb_a11_1 is
end entity tb_a11_1;

architecture bench of tb_a11_1 is

  shared variable errCount        : natural;

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

  constant K_WIDTH                : natural := CO_K_WIDTH_STD;
  constant QBPP                   : natural := CO_QBPP_STD;
  constant LIMIT                  : natural := CO_LIMIT_STD;
  constant UNARY_WIDTH            : natural := CO_UNARY_WIDTH_STD;
  constant SUFFIX_WIDTH           : natural := CO_SUFFIX_WIDTH_STD;
  constant SUFFIXLEN_WIDTH        : natural := CO_SUFFIXLEN_WIDTH_STD;
  constant MAPPED_ERROR_VAL_WIDTH : natural := CO_MAPPED_ERROR_VAL_WIDTH_STD;
  constant THRESHOLD              : natural := LIMIT - QBPP - 1;

  signal iK                       : unsigned(K_WIDTH - 1 downto 0);
  signal iMappedErrorVal          : unsigned(MAPPED_ERROR_VAL_WIDTH - 1 downto 0);
  signal oUnaryZeros              : unsigned(UNARY_WIDTH - 1 downto 0);
  signal oSuffixLen               : unsigned(SUFFIXLEN_WIDTH - 1 downto 0);
  signal oSuffixVal               : unsigned(SUFFIX_WIDTH - 1 downto 0);

  function pow2 (
    n : natural
  ) return natural is

    variable v : natural := 1;

  begin

    if (n = 0) then
      return 1;
    end if;

    for i in 1 to n loop

      v := v * 2;

    end loop;

    return v;

  end function pow2;

  function lfsr_next (
    s : unsigned(31 downto 0)
  ) return unsigned is

    variable v   : unsigned(31 downto 0) := s;
    variable bit : std_logic;

  begin

    bit := v(31) xor v(21) xor v(1) xor v(0);
    v   := v(30 downto 0) & bit;
    return v;

  end function lfsr_next;

  procedure check_case (
    signal sk      : out unsigned;
    signal smerr   : out unsigned;
    signal sunary  : in unsigned;
    signal ssuflen : in unsigned;
    signal ssufval : in unsigned;
    k_val          : natural;
    merr_val       : natural
  ) is

    variable step      : natural;
    variable highOrder : natural;
    variable lowOrder  : natural;
    variable expUnary  : natural;
    variable expSufLen : natural;
    variable expSufVal : natural;

  begin

    sk    <= to_unsigned(k_val, sk'length);
    smerr <= to_unsigned(merr_val, smerr'length);
    wait for 1 ns;

    step      := pow2(k_val);
    highOrder := merr_val / step;
    lowOrder  := merr_val mod step;

    if (highOrder < THRESHOLD) then
      expUnary  := highOrder;
      expSufLen := k_val;
      expSufVal := lowOrder;
    else
      expUnary  := THRESHOLD;
      expSufLen := QBPP;
      expSufVal := (merr_val - 1) mod pow2(QBPP);
    end if;

    check(sunary = to_unsigned(expUnary, sunary'length),
          "A11.1 unary mismatch: k=" & integer'image(integer(k_val)) &
          " MErr=" & integer'image(integer(merr_val)) &
          " exp=" & integer'image(integer(expUnary)) &
          " got=" & integer'image(to_integer(sunary))
        );

    check(ssuflen = to_unsigned(expSufLen, ssuflen'length),
          "A11.1 suffix length mismatch: k=" & integer'image(integer(k_val)) &
          " MErr=" & integer'image(integer(merr_val)) &
          " exp=" & integer'image(integer(expSufLen)) &
          " got=" & integer'image(to_integer(ssuflen))
        );

    check(ssufval = to_unsigned(expSufVal, ssufval'length),
          "A11.1 suffix value mismatch: k=" & integer'image(integer(k_val)) &
          " MErr=" & integer'image(integer(merr_val)) &
          " exp=" & integer'image(integer(expSufVal)) &
          " got=" & integer'image(to_integer(ssufval))
        );

  end procedure check_case;

begin

  dut : entity work.a11_1_golomb_encoder(behavioral)

    generic map (
      K_WIDTH                => K_WIDTH,
      QBPP                   => QBPP,
      LIMIT                  => LIMIT,
      UNARY_WIDTH            => UNARY_WIDTH,
      SUFFIX_WIDTH           => SUFFIX_WIDTH,
      SUFFIXLEN_WIDTH        => SUFFIXLEN_WIDTH,
      MAPPED_ERROR_VAL_WIDTH => MAPPED_ERROR_VAL_WIDTH
    )
    port map (
      iK                     => iK,
      iMappedErrorVal        => iMappedErrorVal,
      iRiMode                => '0',
      iRunIndex              => (others => '0'),
      oUnaryZeros            => oUnaryZeros,
      oSuffixLen             => oSuffixLen,
      oSuffixVal             => oSuffixVal
    );

  stim : process is

    variable lfsr  : unsigned(31 downto 0) := x"5C71A2E9";
    variable kV    : natural;
    variable merrV : natural;

  begin

    -- Initial values (no defaults — set explicitly here)
    iK              <= (others => '0');
    iMappedErrorVal <= (others => '0');

    -- Directed cases
    check_case(iK, iMappedErrorVal, oUnaryZeros, oSuffixLen, oSuffixVal, 0, 0);
    check_case(iK, iMappedErrorVal, oUnaryZeros, oSuffixLen, oSuffixVal, 2, 9);
    check_case(iK, iMappedErrorVal, oUnaryZeros, oSuffixLen, oSuffixVal, 4, 63);
    check_case(iK, iMappedErrorVal, oUnaryZeros, oSuffixLen, oSuffixVal, 1, (THRESHOLD - 1) * 2 + 1);
    check_case(iK, iMappedErrorVal, oUnaryZeros, oSuffixLen, oSuffixVal, 1, THRESHOLD * 2);
    check_case(iK, iMappedErrorVal, oUnaryZeros, oSuffixLen, oSuffixVal, 0, THRESHOLD);
    check_case(iK, iMappedErrorVal, oUnaryZeros, oSuffixLen, oSuffixVal, QBPP, (2 ** MAPPED_ERROR_VAL_WIDTH) - 1);

    -- Pseudo-random coverage
    for i in 0 to 999 loop

      lfsr  := lfsr_next(lfsr);
      kV    := to_integer(unsigned(lfsr(3 downto 0))) mod (QBPP + 1);
      lfsr  := lfsr_next(lfsr);
      merrV := to_integer(unsigned(lfsr(MAPPED_ERROR_VAL_WIDTH - 1 downto 0)));

      check_case(iK, iMappedErrorVal, oUnaryZeros, oSuffixLen, oSuffixVal, kV, merrV);

    end loop;

    if (errCount > 0) then
      report "tb_A11_1 RESULT: FAIL (" & integer'image(errCount) & " errors)"
        severity failure;
    else
      report "tb_A11_1 RESULT: PASS"
        severity note;
    end if;

    finish;

  end process stim;

end architecture bench;
