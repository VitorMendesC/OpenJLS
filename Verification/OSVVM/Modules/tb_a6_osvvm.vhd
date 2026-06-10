--------------------------------------------------------------------------------
-- OSVVM testbench: a6_prediction_correction (combinational).
--
-- T.87 Code segment A.6: Px += C[Q] when SIGN==+1 else Px -= C[Q]; then clamp to
-- [0, MAXVAL]. Coverage crosses the sign with the saturation region (low/in/high).
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.common.all;

library osvvm;
  context osvvm.OsvvmContext;

library tb_support;
  use tb_support.tb_support_pkg.all;

entity tb_a6_osvvm is
end entity tb_a6_osvvm;

architecture sim of tb_a6_osvvm is

  constant BITNESS : natural := CO_BITNESS_STD;
  constant MAX_VAL : natural := CO_MAX_VAL_STD;
  constant CQ_MIN  : integer := CO_MIN_CQ;
  constant CQ_MAX  : integer := CO_MAX_CQ;

  signal sPxIn  : unsigned(BITNESS - 1 downto 0);
  signal sSign  : std_logic;
  signal sCq    : signed(CO_CQ_WIDTH - 1 downto 0);
  signal sPxOut : unsigned(BITNESS - 1 downto 0);

  -- T.87 A.6 reference. region returned for coverage (0 low / 1 in / 2 high).
  function corrected (
    px   : integer;
    sign : std_logic;
    cq   : integer
  ) return integer is

    variable v : integer;

  begin

    if (sign = CO_SIGN_POS) then
      v := px + cq;
    else
      v := px - cq;
    end if;

    if (v > MAX_VAL) then
      return MAX_VAL;
    elsif (v < 0) then
      return 0;
    else
      return v;
    end if;

  end function corrected;

  function region_of (
    px   : integer;
    sign : std_logic;
    cq   : integer
  ) return integer is

    variable v : integer;

  begin

    if (sign = CO_SIGN_POS) then
      v := px + cq;
    else
      v := px - cq;
    end if;

    if (v < 0) then
      return 0;
    elsif (v > MAX_VAL) then
      return 2;
    else
      return 1;
    end if;

  end function region_of;

begin

  dut : entity work.a6_prediction_correction(behavioral)
    generic map (
      BITNESS => BITNESS,
      MAX_VAL => MAX_VAL
    )
    port map (
      iPx   => sPxIn,
      iSign => sSign,
      iCq   => sCq,
      oPx   => sPxOut
    );

  stim : process is

    variable rv      : RandomPType;
    variable cov     : CoverageIDType;
    constant N_RAND  : natural := 5000;

    procedure drive_check (
      px  : integer;
      sg  : std_logic;
      cq  : integer;
      msg : string
    ) is
    begin

      sPxIn <= to_unsigned(px, BITNESS);
      sSign <= sg;
      sCq   <= to_signed(cq, CO_CQ_WIDTH);
      wait for 1 ns;
      AffirmIfEqual(to_integer(sPxOut), corrected(px, sg, cq),
                    msg & " px=" & integer'image(px) & " cq=" & integer'image(cq));
      ICover(cov, (std_to_int(sg), region_of(px, sg, cq)));

    end procedure drive_check;

  begin

    SetAlertLogName("tb_a6_osvvm");
    SetLogEnable(PASSED, FALSE);
    rv.InitSeed(rv'instance_name);

    cov := NewID("sign x region");
    AddCross(cov, "sign x region", GenBin(0, 1, 2), GenBin(0, 2, 3));

    -- Directed corners.
    drive_check(0, CO_SIGN_POS, CQ_MIN, "low sat pos");
    drive_check(MAX_VAL, CO_SIGN_POS, CQ_MAX, "high sat pos");
    drive_check(MAX_VAL, CO_SIGN_NEG, CQ_MIN, "high sat neg");
    drive_check(0, CO_SIGN_NEG, CQ_MAX, "low sat neg");
    drive_check(MAX_VAL / 2, CO_SIGN_POS, 0, "mid cq0");

    -- Random sweep.
    for i in 1 to N_RAND loop

      if (rv.RandInt(0, 1) = 0) then
        drive_check(rv.RandInt(0, MAX_VAL), CO_SIGN_POS, rv.RandInt(CQ_MIN, CQ_MAX), "rand");
      else
        drive_check(rv.RandInt(0, MAX_VAL), CO_SIGN_NEG, rv.RandInt(CQ_MIN, CQ_MAX), "rand");
      end if;
      exit when IsCovered(cov) and i > 300;

    end loop;

    WriteBin(cov);
    AffirmIf(IsCovered(cov), "sign x region coverage closed");

    end_of_test("tb_a6_osvvm");
    wait;

  end process stim;

end architecture sim;
