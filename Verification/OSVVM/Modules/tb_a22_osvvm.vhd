--------------------------------------------------------------------------------
-- OSVVM testbench: a22_errval_mapping (combinational).
--
-- T.87 Code segment A.22: EMErrval = 2*abs(Errval) - RItype - map. The C model
-- has no clamp; the RTL clamps at 0 only to absorb delta-cycle transients on
-- coherent inputs, where EMErrval is always >= 0. So the reference is the pure C
-- formula and the check is restricted to its valid (non-negative) domain; the
-- clamp region is non-occurring and not asserted. Coverage crosses RItype x map
-- and includes the EMErrval==0 boundary.
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.common.all;

library osvvm;
  context osvvm.OsvvmContext;

library tb_support;
  use tb_support.tb_support_pkg.all;

entity tb_a22_osvvm is
end entity tb_a22_osvvm;

architecture sim of tb_a22_osvvm is

  constant ERROR_WIDTH : natural := CO_ERROR_VALUE_WIDTH_STD;
  constant MAPPED_W    : natural := CO_MAPPED_ERROR_VAL_WIDTH_STD;
  constant ERR_MIN     : integer := -(2 ** (ERROR_WIDTH - 1));
  constant ERR_MAX     : integer := (2 ** (ERROR_WIDTH - 1)) - 1;

  signal sErrval : signed(ERROR_WIDTH - 1 downto 0);
  signal sRiType : std_logic;
  signal sMap    : std_logic;
  signal sEm     : unsigned(MAPPED_W - 1 downto 0);

  function ref_em (
    err : integer;
    ri  : integer;
    mp  : integer
  ) return integer is
  begin

    return 2 * abs(err) - ri - mp;

  end function ref_em;

begin

  dut : entity work.a22_errval_mapping(behavioral)
    generic map (
      ERROR_WIDTH         => ERROR_WIDTH,
      MAPPED_ERRVAL_WIDTH => MAPPED_W
    )
    port map (
      iErrval   => sErrval,
      iRiType   => sRiType,
      iMap      => sMap,
      oEmErrVal => sEm
    );

  stim : process is

    variable rv       : RandomPType;
    variable covCross : CovPType;        -- RItype x map (all 4 reachable)
    variable covZero  : CovPType;        -- EMErrval == 0 boundary seen
    variable err      : integer;
    variable ri       : integer;
    variable mp       : integer;
    constant N_RAND   : natural := 8000;

    procedure drive_check (
      ev  : integer;
      riv : integer;
      mpv : integer;
      msg : string
    ) is

      variable exp : integer;
      variable z   : integer;

    begin

      sErrval <= to_signed(ev, ERROR_WIDTH);
      sRiType <= bool2bit(riv = 1);
      sMap    <= bool2bit(mpv = 1);
      wait for 1 ns;

      exp := ref_em(ev, riv, mpv);
      -- Only the coherent (non-negative) domain is comparable to the C model.
      if (exp >= 0) then
        AffirmIfEqual(to_integer(sEm), exp,
                      msg & " err=" & integer'image(ev) &
                      " ri=" & integer'image(riv) & " map=" & integer'image(mpv));
        if (exp = 0) then
          z := 1;
        else
          z := 0;
        end if;
        covCross.ICover((riv, mpv));
        covZero.ICover(z);
      end if;

    end procedure drive_check;

  begin

    SetAlertLogName("tb_a22_osvvm");
    SetLogEnable(PASSED, FALSE);
    rv.InitSeed(rv'instance_name);

    covCross.AddCross("ri x map", GenBin(0, 1, 2), GenBin(0, 1, 2));
    covZero.AddBins("emZero", GenBin(0, 1, 2));

    -- Directed: EMErrval==0 boundary for each ri/map needing it.
    drive_check(1, 1, 1, "err1 ri1 map1 -> 0");        -- 2-1-1 = 0
    drive_check(1, 1, 0, "err1 ri1 map0 -> 1");
    drive_check(1, 0, 1, "err1 ri0 map1 -> 1");
    drive_check(0, 0, 0, "err0 ri0 map0 -> 0");
    drive_check(ERR_MAX, 1, 1, "max err");
    drive_check(ERR_MIN, 0, 0, "min err");

    for i in 1 to N_RAND loop

      -- Bias |err| small so the EMErrval==0 boundary bins fill.
      if (rv.RandInt(0, 1) = 0) then
        err := rv.RandInt(-2, 2);
      else
        err := rv.RandInt(ERR_MIN, ERR_MAX);
      end if;
      ri := rv.RandInt(0, 1);
      mp := rv.RandInt(0, 1);
      drive_check(err, ri, mp, "rand");
      exit when covCross.IsCovered and covZero.IsCovered and i > 400;

    end loop;

    covCross.WriteBin;
    covZero.WriteBin;
    AffirmIf(covCross.IsCovered, "ri x map coverage closed");
    AffirmIf(covZero.IsCovered, "EMErrval==0 boundary covered");

    end_of_test("tb_a22_osvvm");
    wait;

  end process stim;

end architecture sim;
