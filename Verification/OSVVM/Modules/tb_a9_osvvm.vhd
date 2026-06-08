--------------------------------------------------------------------------------
-- OSVVM testbench: a9_modulo_reduction (combinational).
--
-- Reduces the prediction error into (-RANGE/2, RANGE/2]: add RANGE if negative,
-- then subtract RANGE once the adjusted value reaches ceil(RANGE/2). Coverage
-- crosses the negative-wrap path with the upper-half subtract.
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.common.all;

library osvvm;
  context osvvm.OsvvmContext;

library tb_support;
  use tb_support.tb_support_pkg.all;

entity tb_a9_osvvm is
end entity tb_a9_osvvm;

architecture sim of tb_a9_osvvm is

  constant BITNESS : natural := CO_BITNESS_STD;
  constant RANGE_P : natural := CO_RANGE_STD;
  constant ERR_MIN : integer := -(2 ** BITNESS);
  constant ERR_MAX : integer := (2 ** BITNESS) - 1;

  signal sErrIn  : signed(BITNESS downto 0);
  signal sErrOut : signed(BITNESS downto 0);

  -- T.87 A.9 reference value.
  function ref_mod (
    err : integer
  ) return integer is

    variable adj : integer;

  begin

    if (err < 0) then
      adj := err + RANGE_P;
    else
      adj := err;
    end if;

    if (adj >= (RANGE_P + 1) / 2) then
      return adj - RANGE_P;
    else
      return adj;
    end if;

  end function ref_mod;

  -- adjusted (post negative-wrap) value, for the upper-half coverage axis.
  function adj_of (
    err : integer
  ) return integer is
  begin

    if (err < 0) then
      return err + RANGE_P;
    else
      return err;
    end if;

  end function adj_of;

begin

  dut : entity work.a9_modulo_reduction(behavioral)
    generic map (
      BITNESS => BITNESS,
      RANGE_P => RANGE_P
    )
    port map (
      iErrorVal => sErrIn,
      oErrorVal => sErrOut
    );

  stim : process is

    variable rv      : RandomPType;
    variable cov     : CovPType;
    variable err     : integer;
    variable exp     : integer;
    variable wn      : integer;
    variable gh      : integer;
    constant N_RAND  : natural := 4000;

    procedure drive_check (
      ev  : integer;
      msg : string
    ) is

      variable w : integer;
      variable g : integer;

    begin

      sErrIn <= to_signed(ev, BITNESS + 1);
      wait for 1 ns;
      AffirmIfEqual(to_integer(sErrOut), ref_mod(ev), msg & " err=" & integer'image(ev));

      if (ev < 0) then
        w := 1;
      else
        w := 0;
      end if;
      if (adj_of(ev) >= (RANGE_P + 1) / 2) then
        g := 1;
      else
        g := 0;
      end if;
      cov.ICover((w, g));

    end procedure drive_check;

  begin

    SetAlertLogName("tb_a9_osvvm");
    SetLogEnable(PASSED, FALSE);
    rv.InitSeed(rv'instance_name);

    cov.AddCross("wrapNeg x geHalf", GenBin(0, 1, 2), GenBin(0, 1, 2));

    -- Directed corners.
    drive_check(0, "zero");
    drive_check(ERR_MAX, "max");
    drive_check(ERR_MIN, "min");
    drive_check((RANGE_P + 1) / 2, "exact half");
    drive_check((RANGE_P + 1) / 2 - 1, "just below half");
    drive_check(-1, "neg one");

    -- Random sweep.
    for i in 1 to N_RAND loop

      err := rv.RandInt(ERR_MIN, ERR_MAX);
      drive_check(err, "rand");
      exit when cov.IsCovered and i > 200;

    end loop;

    cov.WriteBin;
    AffirmIf(cov.IsCovered, "wrap/half cross coverage closed");

    end_of_test("tb_a9_osvvm");
    wait;

  end process stim;

end architecture sim;
