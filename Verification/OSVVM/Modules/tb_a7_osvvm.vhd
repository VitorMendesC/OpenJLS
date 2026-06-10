--------------------------------------------------------------------------------
-- OSVVM testbench: a7_prediction_error (combinational).
--
-- ErrorVal = Ix-Px when sign = POS, else Px-Ix. Coverage crosses the sign input
-- with the sign of the resulting error.
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.common.all;

library osvvm;
  context osvvm.OsvvmContext;

library tb_support;
  use tb_support.tb_support_pkg.all;

entity tb_a7_osvvm is
end entity tb_a7_osvvm;

architecture sim of tb_a7_osvvm is

  constant BITNESS : natural := CO_BITNESS_STD;
  constant PX_MAX  : integer := (2 ** BITNESS) - 1;

  signal sIx        : unsigned(BITNESS - 1 downto 0);
  signal sPx        : unsigned(BITNESS - 1 downto 0);
  signal sSign      : std_logic;
  signal sErrorVal  : signed(BITNESS downto 0);

  function ref_err (
    ix   : integer;
    px   : integer;
    sign : std_logic
  ) return integer is
  begin

    if (sign = CO_SIGN_POS) then
      return ix - px;
    else
      return px - ix;
    end if;

  end function ref_err;

  function sgn (
    v : integer
  ) return integer is
  begin

    if (v < 0) then
      return 1;
    else
      return 0;
    end if;

  end function sgn;

begin

  dut : entity work.a7_prediction_error(behavioral)
    generic map (
      BITNESS => BITNESS
    )
    port map (
      iIx       => sIx,
      iPx       => sPx,
      iSign     => sSign,
      oErrorVal => sErrorVal
    );

  stim : process is

    variable rv      : RandomPType;
    variable cov     : CoverageIDType;
    variable ix      : integer;
    variable px      : integer;
    variable sgnIn   : integer;
    variable exp     : integer;
    constant N_RAND  : natural := 4000;

    procedure drive_check (
      ixv  : integer;
      pxv  : integer;
      sgv  : std_logic;
      msg  : string
    ) is

      variable e : integer;

    begin

      sIx   <= to_unsigned(ixv, BITNESS);
      sPx   <= to_unsigned(pxv, BITNESS);
      sSign <= sgv;
      wait for 1 ns;
      e := ref_err(ixv, pxv, sgv);
      AffirmIfEqual(to_integer(sErrorVal), e, msg);
      ICover(cov, (std_to_int(sgv), sgn(e)));

    end procedure drive_check;

  begin

    SetAlertLogName("tb_a7_osvvm");
    SetLogEnable(PASSED, FALSE);
    rv.InitSeed(rv'instance_name);

    cov := NewID("signIn x signErr");
    AddCross(cov, "signIn x signErr", GenBin(0, 1, 2), GenBin(0, 1, 2));

    -- Directed corners.
    drive_check(0, 0, CO_SIGN_POS, "zero pos");
    drive_check(PX_MAX, 0, CO_SIGN_POS, "max pos");
    drive_check(0, PX_MAX, CO_SIGN_POS, "min pos");
    drive_check(PX_MAX, 0, CO_SIGN_NEG, "max neg");
    drive_check(0, PX_MAX, CO_SIGN_NEG, "min neg");

    -- Random sweep.
    for i in 1 to N_RAND loop

      ix    := rv.RandInt(0, PX_MAX);
      px    := rv.RandInt(0, PX_MAX);
      if (rv.RandInt(0, 1) = 0) then
        drive_check(ix, px, CO_SIGN_POS, "rand");
      else
        drive_check(ix, px, CO_SIGN_NEG, "rand");
      end if;
      exit when IsCovered(cov) and i > 200;

    end loop;

    WriteBin(cov);
    AffirmIf(IsCovered(cov), "sign cross coverage closed");

    end_of_test("tb_a7_osvvm");
    wait;

  end process stim;

end architecture sim;
