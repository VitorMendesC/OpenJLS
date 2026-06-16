--------------------------------------------------------------------------------
-- OSVVM testbench: a1_gradient_comp (combinational).
--
-- Local gradient computation: D1=D-B, D2=B-C, D3=C-A. Pure subtraction of
-- unsigned pixel neighbours into signed differences. Reference is integer
-- arithmetic; coverage closes the sign octant of (D1,D2,D3).
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.openjls_pkg.all;

library osvvm;
  context osvvm.OsvvmContext;

library tb_support;
  use tb_support.tb_support_pkg.all;

entity tb_a1_osvvm is
end entity tb_a1_osvvm;

architecture sim of tb_a1_osvvm is

  constant BITNESS : natural := CO_BITNESS_STD;
  constant PX_MAX  : integer := (2 ** BITNESS) - 1;

  signal sA  : unsigned(BITNESS - 1 downto 0);
  signal sB  : unsigned(BITNESS - 1 downto 0);
  signal sC  : unsigned(BITNESS - 1 downto 0);
  signal sD  : unsigned(BITNESS - 1 downto 0);
  signal sD1 : signed(BITNESS downto 0);
  signal sD2 : signed(BITNESS downto 0);
  signal sD3 : signed(BITNESS downto 0);

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

  dut : entity work.a1_gradient_comp(behavioral)
    generic map (
      BITNESS => BITNESS
    )
    port map (
      iA  => sA,
      iB  => sB,
      iC  => sC,
      iD  => sD,
      oD1 => sD1,
      oD2 => sD2,
      oD3 => sD3
    );

  stim : process is

    variable rv      : RandomPType;
    variable cov     : CoverageIDType;
    variable req     : AlertLogIDType;
    variable a       : integer;
    variable b       : integer;
    variable c       : integer;
    variable d       : integer;
    constant N_RAND  : natural := 4000;

    procedure drive_check (
      av : integer;
      bv : integer;
      cv : integer;
      dv : integer;
      msg : string
    ) is
    begin

      sA <= to_unsigned(av, BITNESS);
      sB <= to_unsigned(bv, BITNESS);
      sC <= to_unsigned(cv, BITNESS);
      sD <= to_unsigned(dv, BITNESS);
      wait for 1 ns;
      AffirmIfEqual(req, to_integer(sD1), dv - bv, msg & " D1");
      AffirmIfEqual(req, to_integer(sD2), bv - cv, msg & " D2");
      AffirmIfEqual(req, to_integer(sD3), cv - av, msg & " D3");
      ICover(cov, (sgn(dv - bv), sgn(bv - cv), sgn(cv - av)));

    end procedure drive_check;

  begin

    SetAlertLogName("tb_a1_osvvm");
    SetLogEnable(PASSED, FALSE);
    rv.InitSeed(rv'instance_name);
    req := GetReqID("T87.A1", 200);

    cov := NewID("sgnD1 x sgnD2 x sgnD3");
    AddCross(cov, 
                 "sgnD1 x sgnD2 x sgnD3",
                 GenBin(0, 1, 2),
                 GenBin(0, 1, 2),
                 GenBin(0, 1, 2)
               );

    -- Directed corners.
    drive_check(0, 0, 0, 0, "all-zero");
    drive_check(PX_MAX, PX_MAX, PX_MAX, PX_MAX, "all-max");
    drive_check(0, PX_MAX, 0, PX_MAX, "alternating");
    drive_check(PX_MAX, 0, PX_MAX, 0, "alternating2");

    -- Random sweep.
    for i in 1 to N_RAND loop

      a := rv.RandInt(0, PX_MAX);
      b := rv.RandInt(0, PX_MAX);
      c := rv.RandInt(0, PX_MAX);
      d := rv.RandInt(0, PX_MAX);
      drive_check(a, b, c, d, "rand");
      exit when IsCovered(cov) and i > 200;

    end loop;

    WriteBin(cov);
    AffirmIf(IsCovered(cov), "sign-octant coverage closed");

    end_of_test("tb_a1_osvvm");
    wait;

  end process stim;

end architecture sim;
