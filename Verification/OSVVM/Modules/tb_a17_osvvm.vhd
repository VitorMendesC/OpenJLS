--------------------------------------------------------------------------------
-- OSVVM testbench: a17_run_interruption_index (combinational).
--
-- T.87 Code segment A.17 with NEAR=0: RItype = 1 iff abs(Ra-Rb) <= NEAR, i.e.
-- Ra == Rb. Coverage closes both RItype outcomes (equal case biased in).
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.openjls_pkg.all;

library osvvm;
  context osvvm.OsvvmContext;

library tb_support;
  use tb_support.tb_support_pkg.all;

entity tb_a17_osvvm is
end entity tb_a17_osvvm;

architecture sim of tb_a17_osvvm is

  constant BITNESS : natural := CO_BITNESS_STD;
  constant PX_MAX  : integer := (2 ** BITNESS) - 1;

  signal sRaPix     : unsigned(BITNESS - 1 downto 0);
  signal sRbPix     : unsigned(BITNESS - 1 downto 0);
  signal sRItype : std_logic;

begin

  dut : entity work.a17_run_interruption_index(behavioral)
    generic map (
      BITNESS => BITNESS
    )
    port map (
      iRa     => sRaPix,
      iRb     => sRbPix,
      oRItype => sRItype
    );

  stim : process is

    variable rv      : RandomPType;
    variable cov     : CoverageIDType;
    variable req     : AlertLogIDType;
    variable ra      : integer;
    variable rb      : integer;
    constant N_RAND  : natural := 3000;

    procedure drive_check (
      rav : integer;
      rbv : integer;
      msg : string
    ) is

      variable e : integer;

    begin

      sRaPix <= to_unsigned(rav, BITNESS);
      sRbPix <= to_unsigned(rbv, BITNESS);
      wait for 1 ns;

      if (rav = rbv) then
        e := 1;
      else
        e := 0;
      end if;
      AffirmIfEqual(req, std_to_int(sRItype), e, msg);
      ICover(cov, e);

    end procedure drive_check;

  begin

    SetAlertLogName("tb_a17_osvvm");
    SetLogEnable(PASSED, FALSE);
    rv.InitSeed(rv'instance_name);
    req := GetReqID("T87.A17", 100);
    cov := NewID("RItype");
    AddBins(cov, "RItype", GenBin(0, 1, 2));

    drive_check(0, 0, "equal zero");
    drive_check(PX_MAX, PX_MAX, "equal max");
    drive_check(0, PX_MAX, "unequal");

    for i in 1 to N_RAND loop

      ra := rv.RandInt(0, PX_MAX);
      -- Half the time force equality.
      if (rv.RandInt(0, 1) = 0) then
        rb := ra;
      else
        rb := rv.RandInt(0, PX_MAX);
      end if;
      drive_check(ra, rb, "rand");
      exit when IsCovered(cov) and i > 100;

    end loop;

    WriteBin(cov);
    AffirmIf(IsCovered(cov), "RItype coverage closed");

    end_of_test("tb_a17_osvvm");
    wait;

  end process stim;

end architecture sim;
