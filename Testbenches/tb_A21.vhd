use work.Common.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.env.all;

entity tb_A21 is
end;

architecture bench of tb_A21 is
  shared variable err_count : natural := 0;

  procedure check(cond : boolean; msg : string) is
  begin
    if not cond then
      report msg severity error;
      err_count := err_count + 1;
    end if;
  end procedure;

  constant K_WIDTH  : natural := CO_K_WIDTH_STD;
  constant N_WIDTH  : natural := CO_NQ_WIDTH_STD;
  constant E_WIDTH  : natural := CO_ERROR_VALUE_WIDTH_STD;

  signal iK    : unsigned(K_WIDTH - 1 downto 0) := (others => '0');
  signal iErr  : signed(E_WIDTH - 1 downto 0) := (others => '0');
  signal iNn   : unsigned(N_WIDTH - 1 downto 0) := (others => '0');
  signal iNq   : unsigned(N_WIDTH - 1 downto 0) := (others => '0');
  signal oMap  : std_logic;

  procedure check_case(
    kv, errv, nnv, nqv : integer;
    exp               : std_logic;
    map_actual        : std_logic
  ) is
  begin
    check(map_actual = exp,
      "A21 map mismatch: k=" & integer'image(kv) &
      " err=" & integer'image(errv) &
      " Nn=" & integer'image(nnv) &
      " Nq=" & integer'image(nqv) &
      " exp=" & std_logic'image(exp) &
      " got=" & std_logic'image(map_actual)
    );
  end procedure;

begin

  dut : entity work.A21_compute_map
    generic map(
      K_WIDTH   => K_WIDTH,
      N_WIDTH   => N_WIDTH,
      ERR_WIDTH => E_WIDTH
    )
    port map(
      iK      => iK,
      iErrval => iErr,
      iNn     => iNn,
      iNq     => iNq,
      oMap    => oMap
    );

  stim : process
  begin
    -- Branch 1: k=0, err>0, 2*Nn < N
    iK   <= to_unsigned(0, iK'length);
    iErr <= to_signed(5, iErr'length);
    iNn  <= to_unsigned(2, iNn'length);
    iNq  <= to_unsigned(10, iNq'length);
    wait for 1 ns;
    check_case(0, 5, 2, 10, '1', oMap);
    -- Branch 2: err<0, 2*Nn >= N
    iK   <= to_unsigned(0, iK'length);
    iErr <= to_signed(-3, iErr'length);
    iNn  <= to_unsigned(5, iNn'length);
    iNq  <= to_unsigned(8, iNq'length);
    wait for 1 ns;
    check_case(0, -3, 5, 8, '1', oMap);
    -- Branch 3: err<0, k!=0
    iK   <= to_unsigned(2, iK'length);
    iErr <= to_signed(-1, iErr'length);
    iNn  <= to_unsigned(1, iNn'length);
    iNq  <= to_unsigned(10, iNq'length);
    wait for 1 ns;
    check_case(2, -1, 1, 10, '1', oMap);
    -- Else case
    iK   <= to_unsigned(1, iK'length);
    iErr <= to_signed(4, iErr'length);
    iNn  <= to_unsigned(5, iNn'length);
    iNq  <= to_unsigned(8, iNq'length);
    wait for 1 ns;
    check_case(1, 4, 5, 8, '0', oMap);

    if err_count > 0 then
      report "tb_A21 RESULT: FAIL (" & integer'image(err_count) & " errors)" severity failure;
    else
      report "tb_A21 RESULT: PASS" severity note;
    end if;
    finish;
  end process;

end;
