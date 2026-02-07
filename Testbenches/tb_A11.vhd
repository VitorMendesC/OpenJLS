use work.Common.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.env.all;

entity tb_A11 is
end;

architecture bench of tb_A11 is
  shared variable err_count : natural := 0;

  procedure check(cond : boolean; msg : string) is
  begin
    if not cond then
      report msg severity error;
      err_count := err_count + 1;
    end if;
  end procedure;

  constant BITNESS                : natural := CO_BITNESS_STD;
  constant N_WIDTH                : natural := CO_NQ_WIDTH_STD;
  constant B_WIDTH                : natural := CO_BQ_WIDTH_STD;
  constant K_WIDTH                : natural := CO_K_WIDTH_STD;
  constant ERROR_VALUE_WIDTH      : natural := CO_ERROR_VALUE_WIDTH_STD;
  constant MAPPED_ERROR_VAL_WIDTH : natural := CO_MAPPED_ERROR_VAL_WIDTH_STD;

  signal iK              : unsigned(K_WIDTH - 1 downto 0) := (others => '0');
  signal iBq             : signed(B_WIDTH - 1 downto 0) := (others => '0');
  signal iNq             : unsigned(N_WIDTH - 1 downto 0) := (others => '0');
  signal iErrorVal       : signed(ERROR_VALUE_WIDTH - 1 downto 0) := (others => '0');
  signal oMappedErrorN0  : unsigned(MAPPED_ERROR_VAL_WIDTH - 1 downto 0);
  signal oMappedErrorN2  : unsigned(MAPPED_ERROR_VAL_WIDTH - 1 downto 0);

  function model_map(
    errval : integer;
    bq_val : integer;
    nq_val : integer;
    k_val  : integer;
    near_v : integer
  ) return natural is
    variable is_special : boolean;
    variable mapped     : integer;
  begin
    is_special := (near_v = 0) and (k_val = 0) and ((2 * bq_val) <= (-nq_val));

    if is_special then
      if errval >= 0 then
        mapped := (2 * errval) + 1;
      else
        mapped := -2 * (errval + 1);
      end if;
    else
      if errval >= 0 then
        mapped := 2 * errval;
      else
        mapped := -2 * errval - 1;
      end if;
    end if;

    return natural(mapped);
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
    signal sK      : out unsigned;
    signal sBq     : out signed;
    signal sNq     : out unsigned;
    signal sErr    : out signed;
    signal sOutN0  : in unsigned;
    signal sOutN2  : in unsigned;
    err_val        : integer;
    bq_val         : integer;
    nq_val         : integer;
    k_val          : integer
  ) is
    variable exp_n0 : natural;
    variable exp_n2 : natural;
  begin
    sK   <= to_unsigned(k_val, sK'length);
    sBq  <= to_signed(bq_val, sBq'length);
    sNq  <= to_unsigned(nq_val, sNq'length);
    sErr <= to_signed(err_val, sErr'length);
    wait for 1 ns;

    exp_n0 := model_map(err_val, bq_val, nq_val, k_val, 0);
    exp_n2 := model_map(err_val, bq_val, nq_val, k_val, 2);

    check(sOutN0 = to_unsigned(exp_n0, sOutN0'length),
      "A11 NEAR=0 mismatch: Errval=" & integer'image(err_val) &
      " Bq=" & integer'image(bq_val) &
      " Nq=" & integer'image(nq_val) &
      " K=" & integer'image(k_val) &
      " exp=" & integer'image(integer(exp_n0)) &
      " got=" & integer'image(to_integer(sOutN0))
    );

    check(sOutN2 = to_unsigned(exp_n2, sOutN2'length),
      "A11 NEAR=2 mismatch: Errval=" & integer'image(err_val) &
      " Bq=" & integer'image(bq_val) &
      " Nq=" & integer'image(nq_val) &
      " K=" & integer'image(k_val) &
      " exp=" & integer'image(integer(exp_n2)) &
      " got=" & integer'image(to_integer(sOutN2))
    );
  end procedure;
begin
  dut_near0 : entity work.A11_error_mapping
    generic map(
      BITNESS                => BITNESS,
      N_WIDTH                => N_WIDTH,
      B_WIDTH                => B_WIDTH,
      K_WIDTH                => K_WIDTH,
      ERROR_VALUE_WIDTH      => ERROR_VALUE_WIDTH,
      MAPPED_ERROR_VAL_WIDTH => MAPPED_ERROR_VAL_WIDTH,
      NEAR                   => 0
    )
    port map(
      iK              => iK,
      iBq             => iBq,
      iNq             => iNq,
      iErrorVal       => iErrorVal,
      oMappedErrorVal => oMappedErrorN0
    );

  dut_near2 : entity work.A11_error_mapping
    generic map(
      BITNESS                => BITNESS,
      N_WIDTH                => N_WIDTH,
      B_WIDTH                => B_WIDTH,
      K_WIDTH                => K_WIDTH,
      ERROR_VALUE_WIDTH      => ERROR_VALUE_WIDTH,
      MAPPED_ERROR_VAL_WIDTH => MAPPED_ERROR_VAL_WIDTH,
      NEAR                   => 2
    )
    port map(
      iK              => iK,
      iBq             => iBq,
      iNq             => iNq,
      iErrorVal       => iErrorVal,
      oMappedErrorVal => oMappedErrorN2
    );

  stim : process
    variable lfsr   : unsigned(31 downto 0) := x"79A31C4D";
    variable err_v  : integer;
    variable bq_v   : integer;
    variable nq_v   : integer;
    variable k_v    : integer;
  begin
    -- Directed cases
    check_case(iK, iBq, iNq, iErrorVal, oMappedErrorN0, oMappedErrorN2, 3, -5, 10, 0);
    check_case(iK, iBq, iNq, iErrorVal, oMappedErrorN0, oMappedErrorN2, -3, -5, 10, 0);
    check_case(iK, iBq, iNq, iErrorVal, oMappedErrorN0, oMappedErrorN2, 3, -4, 10, 0);
    check_case(iK, iBq, iNq, iErrorVal, oMappedErrorN0, oMappedErrorN2, -3, -4, 10, 0);
    check_case(iK, iBq, iNq, iErrorVal, oMappedErrorN0, oMappedErrorN2, 12, -20, 15, 1);
    check_case(iK, iBq, iNq, iErrorVal, oMappedErrorN0, oMappedErrorN2, -12, -20, 15, 1);
    check_case(iK, iBq, iNq, iErrorVal, oMappedErrorN0, oMappedErrorN2, 0, -1, 1, 0);
    check_case(iK, iBq, iNq, iErrorVal, oMappedErrorN0, oMappedErrorN2, -1, -1, 1, 0);
    check_case(iK, iBq, iNq, iErrorVal, oMappedErrorN0, oMappedErrorN2, 4095, -100, 63, 0);
    check_case(iK, iBq, iNq, iErrorVal, oMappedErrorN0, oMappedErrorN2, -4096, -100, 63, 0);

    -- Pseudo-random coverage
    for i in 0 to 999 loop
      lfsr  := lfsr_next(lfsr);
      err_v := to_integer(signed(lfsr(BITNESS downto 0)));

      lfsr := lfsr_next(lfsr);
      bq_v := to_integer(signed(lfsr(15 downto 0)));

      lfsr := lfsr_next(lfsr);
      nq_v := to_integer(unsigned(lfsr(N_WIDTH - 1 downto 0)));
      if nq_v = 0 then
        nq_v := 1;
      end if;

      lfsr := lfsr_next(lfsr);
      k_v  := to_integer(unsigned(lfsr(3 downto 0))) mod 8;

      check_case(iK, iBq, iNq, iErrorVal, oMappedErrorN0, oMappedErrorN2, err_v, bq_v, nq_v, k_v);
    end loop;

    if err_count > 0 then
      report "tb_A11 RESULT: FAIL (" & integer'image(err_count) & " errors)" severity failure;
    else
      report "tb_A11 RESULT: PASS" severity note;
    end if;
    finish;
  end process;
end;
