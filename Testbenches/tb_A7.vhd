use work.Common.all;

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

use std.env.all;

entity tb_A7 is
end;

architecture bench of tb_A7 is
  shared variable err_count : natural := 0;

  procedure check(cond : boolean; msg : string) is
  begin
    if not cond then
      report msg severity error;
      err_count := err_count + 1;
    end if;
  end procedure;

  -- Clock period
  constant clk_period : time := 5 ns;
  -- Generics
  constant BITNESS : natural range 8 to 16 := 12;
  -- Ports
  signal iIx       : unsigned (BITNESS - 1 downto 0);
  signal iPx       : unsigned (BITNESS - 1 downto 0);
  signal iSign     : std_logic;
  signal oErrorVal : signed (BITNESS downto 0);

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
    if sign_val = CO_SIGN_NEG then
      exp_v := - exp_v;
    end if;

    check(oErrorVal = exp_v,
      "A7 mismatch: Ix=" & integer'image(ix_val) &
      " Px=" & integer'image(px_val) &
      " Sign=" & std_logic'image(sign_val) &
      " Exp=" & integer'image(to_integer(exp_v)) &
      " Got=" & integer'image(to_integer(oErrorVal))
    );
  end procedure;
begin

  A7_prediction_error_inst : entity work.A7_prediction_error
    generic map(
      BITNESS => BITNESS
    )
    port map
    (
      iIx       => iIx,
      iPx       => iPx,
      iSign     => iSign,
      oErrorVal => oErrorVal
    );

  stim_proc : process
  begin
    -- Basic cases
    check_case(iIx, iPx, iSign, 0, 0, CO_SIGN_POS);
    check_case(iIx, iPx, iSign, 0, 0, CO_SIGN_NEG);
    check_case(iIx, iPx, iSign, 10, 3, CO_SIGN_POS);
    check_case(iIx, iPx, iSign, 10, 3, CO_SIGN_NEG);
    check_case(iIx, iPx, iSign, 3, 10, CO_SIGN_POS);
    check_case(iIx, iPx, iSign, 3, 10, CO_SIGN_NEG);

    -- Extremes within BITNESS
    check_case(iIx, iPx, iSign, 0, 2 ** BITNESS - 1, CO_SIGN_POS);
    check_case(iIx, iPx, iSign, 0, 2 ** BITNESS - 1, CO_SIGN_NEG);
    check_case(iIx, iPx, iSign, 2 ** BITNESS - 1, 0, CO_SIGN_POS);
    check_case(iIx, iPx, iSign, 2 ** BITNESS - 1, 0, CO_SIGN_NEG);
    check_case(iIx, iPx, iSign, 2 ** BITNESS - 1, 2 ** BITNESS - 1, CO_SIGN_POS);
    check_case(iIx, iPx, iSign, 2 ** BITNESS - 1, 2 ** BITNESS - 1, CO_SIGN_NEG);

    if err_count > 0 then
      report "tb_A7 RESULT: FAIL (" & integer'image(err_count) & " errors)" severity failure;
    else
      report "tb_A7 RESULT: PASS" severity note;
    end if;
    finish;
  end process;
end;
