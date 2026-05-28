use work.common.all;

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use std.env.all;

library openlogic_base;
  use openlogic_base.olo_base_pkg_math.log2ceil;

entity tb_a10 is
end entity tb_a10;

architecture bench of tb_a10 is

  shared variable errCount : natural;

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

  -- Generics
  constant A_WIDTH         : natural := CO_AQ_WIDTH_STD;
  constant N_WIDTH         : natural := CO_NQ_WIDTH_STD;
  constant K_WIDTH         : natural := log2ceil(CO_AQ_WIDTH_STD) + 1;
  constant MAX_K           : natural := A_WIDTH;
  constant DIR_A_WIDTH     : natural := math_min(A_WIDTH, 12);
  constant DIR_A_MAX       : natural := 2 ** DIR_A_WIDTH - 1;
  constant DIR_A_POW2      : natural := 2 ** (DIR_A_WIDTH - 1);

  -- Ports
  signal iNq               : unsigned (N_WIDTH - 1 downto 0);
  signal iAq               : unsigned (A_WIDTH - 1 downto 0);
  signal oK                : unsigned (K_WIDTH - 1 downto 0);

  function compute_k (
    nq : unsigned;
    aq : unsigned
  ) return unsigned is

    constant TMP_WIDTH : natural := aq'length + 1;
    variable vK        : unsigned(K_WIDTH - 1 downto 0);
    variable vNqTmp    : unsigned(TMP_WIDTH - 1 downto 0);
    variable vAqTmp    : unsigned(TMP_WIDTH - 1 downto 0);

  begin

    vNqTmp := resize(nq, TMP_WIDTH);
    vAqTmp := resize(aq, TMP_WIDTH);

    for i in 0 to MAX_K loop

      if (vNqTmp < vAqTmp) then
        vNqTmp := shift_left(vNqTmp, 1);
        vK     := vK + 1;
      else
        exit;
      end if;

    end loop;

    return vK;

  end function compute_k;

  function lfsr_next (
    s : unsigned(31 downto 0)
  ) return unsigned is

    variable v   : unsigned(31 downto 0);
    variable bit : std_logic;

  begin

    bit := v(31) xor v(21) xor v(1) xor v(0);
    v   := v(30 downto 0) & bit;
    return v;

  end function lfsr_next;

  procedure check_case (
    signal snq : out unsigned;
    signal saq : out unsigned;
    signal sk  : in unsigned;
    nq_val     : natural;
    aq_val     : natural
  ) is

    variable expK : unsigned(K_WIDTH - 1 downto 0);

  begin

    snq  <= to_unsigned(nq_val, snq'length);
    saq  <= to_unsigned(aq_val, saq'length);
    wait for 1 ns;
    expK := compute_k(to_unsigned(nq_val, snq'length),
                      to_unsigned(aq_val, saq'length));
    check(sk = expK,
          "A10 mismatch: Nq=" & integer'image(nq_val) &
          " Aq=" & integer'image(aq_val) &
          " ExpK=" & integer'image(to_integer(expK)) &
          " GotK=" & integer'image(to_integer(sk))
        );

  end procedure check_case;

begin

  a10_compute_k_inst : entity work.a10_compute_k(behavioral)

    generic map (
      N_WIDTH => N_WIDTH,
      A_WIDTH => A_WIDTH,
      K_WIDTH => K_WIDTH
    )
    port map (
      iNq     => iNq,
      iAq     => iAq,
      oK      => oK
    );

  stim : process is

    variable lfsr : unsigned(31 downto 0);
    variable nq   : natural;
    variable aq   : natural;

  begin

    -- Directed cases
    check_case(iNq, iAq, oK, 10, 3);                                         -- already >=, k=0
    check_case(iNq, iAq, oK, 3, 10);                                         -- shifts twice, k=2
    check_case(iNq, iAq, oK, 7, 8);                                          -- k=1
    check_case(iNq, iAq, oK, 8, 8);                                          -- k=0
    check_case(iNq, iAq, oK, 1, DIR_A_POW2);                                 -- k=DIR_A_WIDTH-1
    check_case(iNq, iAq, oK, 1, DIR_A_MAX);                                  -- k=DIR_A_WIDTH
    check_case(iNq, iAq, oK, 1, 0);                                          -- k=0
    check_case(iNq, iAq, oK, 1, 1);                                          -- k=0
    check_case(iNq, iAq, oK, 1, 2);                                          -- k=1
    check_case(iNq, iAq, oK, 1, 2048);                                       -- k=11 for DIR_A_WIDTH=12

    -- Pseudo-random coverage
    for i in 0 to 999 loop

      lfsr := lfsr_next(lfsr);
      nq   := to_integer(lfsr(N_WIDTH - 1 downto 0));

      if (nq = 0) then
        nq := 1;                                                             -- Nq is initialized to 1 per T.87
      end if;

      lfsr := lfsr_next(lfsr);
      -- Clamp to 31 bits to keep aq within NATURAL range (2^31-1 max).
      aq := to_integer(lfsr(math_min(A_WIDTH, 31) - 1 downto 0));
      check_case(iNq, iAq, oK, nq, aq);

    end loop;

    if (errCount > 0) then
      report "tb_A10 RESULT: FAIL (" & integer'image(errCount) & " errors)"
        severity failure;
    else
      report "tb_A10 RESULT: PASS"
        severity note;
    end if;

    finish;

  end process stim;

end architecture bench;
