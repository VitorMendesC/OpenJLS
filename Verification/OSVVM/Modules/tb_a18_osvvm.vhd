--------------------------------------------------------------------------------
-- OSVVM testbench: a18_run_interruption_prediction_error (combinational).
--
-- T.87 Code segment A.18: Px = (RItype==1)? Ra : Rb; Errval = Ix - Px.
-- Coverage crosses RItype with the sign of the resulting error.
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.common.all;

library osvvm;
  context osvvm.OsvvmContext;

library tb_support;
  use tb_support.tb_support_pkg.all;

entity tb_a18_osvvm is
end entity tb_a18_osvvm;

architecture sim of tb_a18_osvvm is

  constant BITNESS : natural := CO_BITNESS_STD;
  constant PX_MAX  : integer := (2 ** BITNESS) - 1;

  signal sRItype : std_logic;
  signal sRaPix     : unsigned(BITNESS - 1 downto 0);
  signal sRbPix     : unsigned(BITNESS - 1 downto 0);
  signal sIx     : unsigned(BITNESS - 1 downto 0);
  signal sErrval : signed(BITNESS downto 0);

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

  dut : entity work.a18_run_interruption_prediction_error(behavioral)
    generic map (
      BITNESS => BITNESS
    )
    port map (
      iRItype => sRItype,
      iRa     => sRaPix,
      iRb     => sRbPix,
      iIx     => sIx,
      oErrval => sErrval
    );

  stim : process is

    variable rv      : RandomPType;
    variable cov     : CovPType;
    constant N_RAND  : natural := 4000;

    procedure drive_check (
      ri  : std_logic;
      ra  : integer;
      rb  : integer;
      ix  : integer;
      msg : string
    ) is

      variable px : integer;
      variable e  : integer;

    begin

      sRItype <= ri;
      sRaPix     <= to_unsigned(ra, BITNESS);
      sRbPix     <= to_unsigned(rb, BITNESS);
      sIx     <= to_unsigned(ix, BITNESS);
      wait for 1 ns;

      if (ri = '1') then
        px := ra;
      else
        px := rb;
      end if;
      e := ix - px;
      AffirmIfEqual(to_integer(sErrval), e, msg);
      cov.ICover((std_to_int(ri), sgn(e)));

    end procedure drive_check;

  begin

    SetAlertLogName("tb_a18_osvvm");
    SetLogEnable(PASSED, FALSE);
    rv.InitSeed(rv'instance_name);
    cov.AddCross("RItype x errSign", GenBin(0, 1, 2), GenBin(0, 1, 2));

    drive_check('1', 0, PX_MAX, PX_MAX, "ri1 pos");
    drive_check('1', PX_MAX, 0, 0, "ri1 neg");
    drive_check('0', PX_MAX, 0, PX_MAX, "ri0 pos");
    drive_check('0', 0, PX_MAX, 0, "ri0 neg");

    for i in 1 to N_RAND loop

      if (rv.RandInt(0, 1) = 0) then
        drive_check('1', rv.RandInt(0, PX_MAX), rv.RandInt(0, PX_MAX), rv.RandInt(0, PX_MAX), "rand ri1");
      else
        drive_check('0', rv.RandInt(0, PX_MAX), rv.RandInt(0, PX_MAX), rv.RandInt(0, PX_MAX), "rand ri0");
      end if;
      exit when cov.IsCovered and i > 200;

    end loop;

    cov.WriteBin;
    AffirmIf(cov.IsCovered, "RItype x errSign coverage closed");

    end_of_test("tb_a18_osvvm");
    wait;

  end process stim;

end architecture sim;
