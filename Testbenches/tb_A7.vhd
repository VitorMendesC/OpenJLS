
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_A7 is
end;

architecture bench of tb_A7 is
  -- Clock period
  constant clk_period : time := 5 ns;
  -- Generics
  constant BITNESS : natural range 8 to 16 := 12;
  -- Ports
  signal iIx         : unsigned (BITNESS - 1 downto 0);
  signal iPx         : unsigned (BITNESS - 1 downto 0);
  signal iSign       : std_logic;
  signal oErrorValue : signed (BITNESS downto 0);

  procedure check_case(
    signal iIx_s   : out unsigned(BITNESS - 1 downto 0);
    signal iPx_s   : out unsigned(BITNESS - 1 downto 0);
    signal iSign_s : out std_logic;
    ix_val         : natural;
    px_val         : natural;
    sign_val       : std_logic
  ) is
    variable ix_u  : unsigned(BITNESS - 1 downto 0);
    variable px_u  : unsigned(BITNESS - 1 downto 0);
    variable exp_v : signed(BITNESS downto 0);
  begin
    ix_u := to_unsigned(ix_val, BITNESS);
    px_u := to_unsigned(px_val, BITNESS);

    iIx_s   <= ix_u;
    iPx_s   <= px_u;
    iSign_s <= sign_val;
    wait for 1 ns;

    exp_v := signed('0' & ix_u) - signed('0' & px_u);
    if sign_val = '1' then
      exp_v := - exp_v;
    end if;

    assert oErrorValue = exp_v
    report "A7 mismatch: Ix=" & integer'image(ix_val) &
      " Px=" & integer'image(px_val) &
      " Sign=" & std_logic'image(sign_val) &
      " Exp=" & integer'image(to_integer(exp_v)) &
      " Got=" & integer'image(to_integer(oErrorValue))
      severity error;
  end procedure;
begin

  A7_prediction_error_inst : entity work.A7_prediction_error
    generic map(
      BITNESS => BITNESS
    )
    port map
    (
      iIx         => iIx,
      iPx         => iPx,
      iSign       => iSign,
      oErrorValue => oErrorValue
    );

  stim_proc : process
  begin
    -- Basic cases
    check_case(iIx, iPx, iSign, 0, 0, '0');
    check_case(iIx, iPx, iSign, 0, 0, '1');
    check_case(iIx, iPx, iSign, 10, 3, '0');
    check_case(iIx, iPx, iSign, 10, 3, '1');
    check_case(iIx, iPx, iSign, 3, 10, '0');
    check_case(iIx, iPx, iSign, 3, 10, '1');

    -- Extremes within BITNESS
    check_case(iIx, iPx, iSign, 0, 2 ** BITNESS - 1, '0');
    check_case(iIx, iPx, iSign, 0, 2 ** BITNESS - 1, '1');
    check_case(iIx, iPx, iSign, 2 ** BITNESS - 1, 0, '0');
    check_case(iIx, iPx, iSign, 2 ** BITNESS - 1, 0, '1');
    check_case(iIx, iPx, iSign, 2 ** BITNESS - 1, 2 ** BITNESS - 1, '0');
    check_case(iIx, iPx, iSign, 2 ** BITNESS - 1, 2 ** BITNESS - 1, '1');

    report "tb_A7 completed" severity note;
    wait;
  end process;
end;
