library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.Common.all;

library openlogic_base;
use openlogic_base.olo_base_pkg_math.log2ceil;

entity tb_A10 is
end;

architecture bench of tb_A10 is
  -- Generics
  constant A_WIDTH : natural := CO_AQ_WIDTH_STD;
  constant N_WIDTH : natural := CO_NQ_WIDTH_STD;
  constant K_WIDTH : natural := log2ceil(CO_AQ_WIDTH_STD) + 1;
  constant MAX_K   : natural := A_WIDTH;
  constant DIR_A_WIDTH : natural := minimum(A_WIDTH, 12);
  constant DIR_A_MAX   : natural := 2 ** DIR_A_WIDTH - 1;
  constant DIR_A_POW2  : natural := 2 ** (DIR_A_WIDTH - 1);

  -- Ports
  signal iNq : unsigned (N_WIDTH - 1 downto 0);
  signal iAq : unsigned (A_WIDTH - 1 downto 0);
  signal oK  : unsigned (K_WIDTH - 1 downto 0);

  function compute_k(nq : unsigned; aq : unsigned) return unsigned is
    constant TMP_WIDTH : natural := aq'length + 1;
    variable vK     : unsigned(K_WIDTH - 1 downto 0) := (others => '0');
    variable vNqTmp : unsigned(TMP_WIDTH - 1 downto 0);
    variable vAqTmp : unsigned(TMP_WIDTH - 1 downto 0);
  begin
    vNqTmp := resize(nq, TMP_WIDTH);
    vAqTmp := resize(aq, TMP_WIDTH);

    for i in 0 to MAX_K loop
      if vNqTmp < vAqTmp then
        vNqTmp := shift_left(vNqTmp, 1);
        vK     := vK + 1;
      else
        exit;
      end if;
    end loop;
    return vK;
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
    signal sNq  : out unsigned;
    signal sAq  : out unsigned;
    signal sK   : in unsigned;
    nq_val      : natural;
    aq_val      : natural
  ) is
    variable exp_k : unsigned(K_WIDTH - 1 downto 0);
  begin
    sNq <= to_unsigned(nq_val, sNq'length);
    sAq <= to_unsigned(aq_val, sAq'length);
    wait for 1 ns;
    exp_k := compute_k(to_unsigned(nq_val, sNq'length),
                       to_unsigned(aq_val, sAq'length));
    assert sK = exp_k
      report "A10 mismatch: Nq=" & integer'image(nq_val) &
             " Aq=" & integer'image(aq_val) &
             " ExpK=" & integer'image(to_integer(exp_k)) &
             " GotK=" & integer'image(to_integer(sK))
      severity error;
  end procedure;
begin

  A10_compute_k_inst : entity work.A10_compute_k
    generic map(
      N_WIDTH => N_WIDTH,
      A_WIDTH => A_WIDTH,
      K_WIDTH => K_WIDTH
    )
    port map
    (
      iNq => iNq,
      iAq => iAq,
      oK  => oK
    );

  stim : process
    variable lfsr : unsigned(31 downto 0) := x"1F2E3D4C";
    variable nq   : natural;
    variable aq   : natural;
  begin
    -- Directed cases
    check_case(iNq, iAq, oK, 10, 3);  -- already >=, k=0
    check_case(iNq, iAq, oK, 3, 10);  -- shifts twice, k=2
    check_case(iNq, iAq, oK, 7, 8);   -- k=1
    check_case(iNq, iAq, oK, 8, 8);   -- k=0
    check_case(iNq, iAq, oK, 1, DIR_A_POW2); -- k=DIR_A_WIDTH-1
    check_case(iNq, iAq, oK, 1, DIR_A_MAX);  -- k=DIR_A_WIDTH
    check_case(iNq, iAq, oK, 1, 0);   -- k=0
    check_case(iNq, iAq, oK, 1, 1);   -- k=0
    check_case(iNq, iAq, oK, 1, 2);   -- k=1
    check_case(iNq, iAq, oK, 1, 2048); -- k=11 for DIR_A_WIDTH=12

    -- Pseudo-random coverage
    for i in 0 to 999 loop
      lfsr := lfsr_next(lfsr);
      nq   := to_integer(lfsr(N_WIDTH - 1 downto 0));
      if nq = 0 then
        nq := 1; -- Nq is initialized to 1 per T.87
      end if;
      lfsr := lfsr_next(lfsr);
      aq   := to_integer(lfsr(A_WIDTH - 1 downto 0));
      check_case(iNq, iAq, oK, nq, aq);
    end loop;

    report "tb_A10 completed" severity note;
    wait;
  end process;
end;
