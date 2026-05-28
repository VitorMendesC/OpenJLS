use work.common.all;

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use std.env.all;

entity tb_a7 is
end entity tb_a7;

architecture bench of tb_a7 is

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

  -- Clock period
  constant CLK_PERIOD      : time := 5 ns;
  -- Generics
  constant BITNESS         : natural range 8 to 16 := 12;
  -- Ports
  signal iIx               : unsigned (BITNESS - 1 downto 0);
  signal iPx               : unsigned (BITNESS - 1 downto 0);
  signal iSign             : std_logic;
  signal oErrorVal         : signed (BITNESS downto 0);

  procedure check_case (
    signal iix_s   : out unsigned(BITNESS - 1 downto 0);
    signal ipx_s   : out unsigned(BITNESS - 1 downto 0);
    signal isign_s : out std_logic;
    ix_val         : natural;
    px_val         : natural;
    sign_val       : std_logic
  ) is

    variable ixU  : unsigned(BITNESS - 1 downto 0);
    variable pxU  : unsigned(BITNESS - 1 downto 0);
    variable expV : signed(BITNESS downto 0);

  begin

    ixU := to_unsigned(ix_val, BITNESS);
    pxU := to_unsigned(px_val, BITNESS);

    iix_s   <= ixU;
    ipx_s   <= pxU;
    isign_s <= sign_val;
    wait for 1 ns;

    expV := signed('0' & ixU) - signed('0' & pxU);

    if (sign_val = CO_SIGN_NEG) then
      expV := - expV;
    end if;

    check(oErrorVal = expV,
          "A7 mismatch: Ix=" & integer'image(ix_val) &
          " Px=" & integer'image(px_val) &
          " Sign=" & std_logic'image(sign_val) &
          " Exp=" & integer'image(to_integer(expV)) &
          " Got=" & integer'image(to_integer(oErrorVal))
        );

  end procedure check_case;

begin

  a7_prediction_error_inst : entity work.a7_prediction_error(behavioral)

    generic map (
      BITNESS   => BITNESS
    )
    port map (
      iIx       => iIx,
      iPx       => iPx,
      iSign     => iSign,
      oErrorVal => oErrorVal
    );

  stim_proc : process is
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

    if (errCount > 0) then
      report "tb_A7 RESULT: FAIL (" & integer'image(errCount) & " errors)"
        severity failure;
    else
      report "tb_A7 RESULT: PASS"
        severity note;
    end if;

    finish;

  end process stim_proc;

end architecture bench;
