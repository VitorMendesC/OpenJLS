use work.common.all;

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use std.env.all;

entity tb_a11 is
end entity tb_a11;

architecture bench of tb_a11 is

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

  constant BITNESS                : natural := CO_BITNESS_STD;
  constant N_WIDTH                : natural := CO_NQ_WIDTH_STD;
  constant B_WIDTH                : natural := CO_BQ_WIDTH_STD;
  constant K_WIDTH                : natural := CO_K_WIDTH_STD;
  constant ERROR_WIDTH            : natural := CO_ERROR_VALUE_WIDTH_STD;
  constant MAPPED_ERROR_VAL_WIDTH : natural := CO_MAPPED_ERROR_VAL_WIDTH_STD;

  signal iK                       : unsigned(K_WIDTH - 1 downto 0);
  signal iBq                      : signed(B_WIDTH - 1 downto 0);
  signal iNq                      : unsigned(N_WIDTH - 1 downto 0);
  signal iErrorVal                : signed(ERROR_WIDTH - 1 downto 0);
  signal oMappedErrorN0           : unsigned(MAPPED_ERROR_VAL_WIDTH - 1 downto 0);

  function model_map (
    errval : integer;
    bq_val : integer;
    nq_val : integer;
    k_val  : integer
  ) return natural is

    variable isSpecial : boolean;
    variable mapped    : integer;

  begin

    isSpecial := (k_val = 0) and ((2 * bq_val) <= (-nq_val));

    if (isSpecial) then
      if (errval >= 0) then
        mapped := (2 * errval) + 1;
      else
        mapped := - 2 * (errval + 1);
      end if;
    else
      if (errval >= 0) then
        mapped := 2 * errval;
      else
        mapped := - 2 * errval - 1;
      end if;
    end if;

    return natural(mapped);

  end function model_map;

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
    signal sk     : out unsigned;
    signal sbq    : out signed;
    signal snq    : out unsigned;
    signal serr   : out signed;
    signal soutn0 : in unsigned;
    err_val       : integer;
    bq_val        : integer;
    nq_val        : integer;
    k_val         : integer
  ) is

    variable expN0 : natural;

  begin

    sk   <= to_unsigned(k_val, sk'length);
    sbq  <= to_signed(bq_val, sbq'length);
    snq  <= to_unsigned(nq_val, snq'length);
    serr <= to_signed(err_val, serr'length);
    wait for 1 ns;

    expN0 := model_map(err_val, bq_val, nq_val, k_val);

    check(soutn0 = to_unsigned(expN0, soutn0'length),
          "A11 mismatch: Errval=" & integer'image(err_val) &
          " Bq=" & integer'image(bq_val) &
          " Nq=" & integer'image(nq_val) &
          " K=" & integer'image(k_val) &
          " exp=" & integer'image(integer(expN0)) &
          " got=" & integer'image(to_integer(soutn0))
        );

  end procedure check_case;

begin

  dut : entity work.a11_error_mapping(behavioral)

    generic map (
      N_WIDTH                => N_WIDTH,
      B_WIDTH                => B_WIDTH,
      K_WIDTH                => K_WIDTH,
      ERROR_WIDTH            => ERROR_WIDTH,
      MAPPED_ERROR_VAL_WIDTH => MAPPED_ERROR_VAL_WIDTH
    )
    port map (
      iK                     => iK,
      iBq                    => iBq,
      iNq                    => iNq,
      iErrorVal              => iErrorVal,
      oMappedErrorVal        => oMappedErrorN0
    );

  stim : process is

    variable lfsr : unsigned(31 downto 0) := x"6B81C5F2";
    variable errV : integer;
    variable bqV  : integer;
    variable nqV  : integer;
    variable kV   : integer;

  begin

    -- Initial values (no defaults — set explicitly here)
    iK        <= (others => '0');
    iBq       <= (others => '0');
    iNq       <= (others => '0');
    iErrorVal <= (others => '0');

    -- Directed cases
    check_case(iK, iBq, iNq, iErrorVal, oMappedErrorN0, 3, -5, 10, 0);
    check_case(iK, iBq, iNq, iErrorVal, oMappedErrorN0, -3, -5, 10, 0);
    check_case(iK, iBq, iNq, iErrorVal, oMappedErrorN0, 3, -4, 10, 0);
    check_case(iK, iBq, iNq, iErrorVal, oMappedErrorN0, -3, -4, 10, 0);
    check_case(iK, iBq, iNq, iErrorVal, oMappedErrorN0, 12, -20, 15, 1);
    check_case(iK, iBq, iNq, iErrorVal, oMappedErrorN0, -12, -20, 15, 1);
    check_case(iK, iBq, iNq, iErrorVal, oMappedErrorN0, 0, -1, 1, 0);
    check_case(iK, iBq, iNq, iErrorVal, oMappedErrorN0, -1, -1, 1, 0);
    check_case(iK, iBq, iNq, iErrorVal, oMappedErrorN0, 4095, -100, 63, 0);
    check_case(iK, iBq, iNq, iErrorVal, oMappedErrorN0, -4096, -100, 63, 0);

    -- Pseudo-random coverage
    for i in 0 to 999 loop

      lfsr := lfsr_next(lfsr);
      errV := to_integer(signed(lfsr(BITNESS downto 0)));

      lfsr := lfsr_next(lfsr);
      bqV  := to_integer(signed(lfsr(B_WIDTH - 1 downto 0)));        -- B only feeds the 2*Bq <= -Nq test; full signed B_WIDTH range

      lfsr := lfsr_next(lfsr);
      nqV  := to_integer(unsigned(lfsr(N_WIDTH - 1 downto 0)));

      if (nqV = 0) then
        nqV := 1;
      end if;

      lfsr := lfsr_next(lfsr);
      kV   := to_integer(unsigned(lfsr(3 downto 0))) mod 8;

      check_case(iK, iBq, iNq, iErrorVal, oMappedErrorN0, errV, bqV, nqV, kV);

    end loop;

    if (errCount > 0) then
      report "tb_A11 RESULT: FAIL (" & integer'image(errCount) & " errors)"
        severity failure;
    else
      report "tb_A11 RESULT: PASS"
        severity note;
    end if;

    finish;

  end process stim;

end architecture bench;
