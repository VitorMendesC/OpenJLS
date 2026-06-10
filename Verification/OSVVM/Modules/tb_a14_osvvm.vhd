--------------------------------------------------------------------------------
-- OSVVM testbench: a14_run_length_determination (combinational, per-pixel).
--
-- The RTL evaluates one iteration of the T.87 A.14 while loop per pixel
-- (NEAR=0 -> the |Ix-RUNval|<=NEAR test is Ix==Ra):
--   runHit  = (Ix == Ra)
--   RUNcnt' = runHit ? RUNcnt+1 : RUNcnt
--   continue = runHit and not EOLine
-- Coverage crosses run-hit with the EOL break.
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.common.all;

library osvvm;
  context osvvm.OsvvmContext;

library tb_support;
  use tb_support.tb_support_pkg.all;

entity tb_a14_osvvm is
end entity tb_a14_osvvm;

architecture sim of tb_a14_osvvm is

  constant BITNESS : natural := CO_BITNESS_STD;
  constant RC_W    : natural := 16;
  constant PX_MAX  : integer := (2 ** BITNESS) - 1;
  constant RC_MOD  : integer := 2 ** RC_W;

  signal sRaPix    : unsigned(BITNESS - 1 downto 0);
  signal sIx       : unsigned(BITNESS - 1 downto 0);
  signal sRunCnt   : unsigned(RC_W - 1 downto 0);
  signal sEol      : std_logic;
  signal sRunCntO  : unsigned(RC_W - 1 downto 0);
  signal sRunHit   : std_logic;
  signal sRunCont  : std_logic;

begin

  dut : entity work.a14_run_length_determination(behavioral)
    generic map (
      BITNESS       => BITNESS,
      RUN_CNT_WIDTH => RC_W
    )
    port map (
      iRa          => sRaPix,
      iIx          => sIx,
      iRunCnt      => sRunCnt,
      iEol         => sEol,
      oRunCnt      => sRunCntO,
      oRunHit      => sRunHit,
      oRunContinue => sRunCont
    );

  stim : process is

    variable rv      : RandomPType;
    variable cov     : CoverageIDType;
    variable ra      : integer;
    variable ix      : integer;
    variable rc      : integer;
    constant N_RAND  : natural := 3000;

    procedure drive_check (
      rav : integer;
      ixv : integer;
      rcv : integer;
      eol : std_logic;
      msg : string
    ) is

      variable hit  : integer;
      variable expC : integer;

    begin

      sRaPix  <= to_unsigned(rav, BITNESS);
      sIx     <= to_unsigned(ixv, BITNESS);
      sRunCnt <= to_unsigned(rcv, RC_W);
      sEol    <= eol;
      wait for 1 ns;

      if (rav = ixv) then
        hit := 1;
      else
        hit := 0;
      end if;

      if (hit = 1) then
        expC := (rcv + 1) mod RC_MOD;
      else
        expC := rcv;
      end if;

      AffirmIfEqual(to_integer(sRunCntO), expC, msg & " runCnt");
      AffirmIfEqual(std_to_int(sRunHit), hit, msg & " runHit");
      AffirmIfEqual(std_to_int(sRunCont), hit * std_to_int(not eol), msg & " continue");
      ICover(cov, (hit, std_to_int(eol)));

    end procedure drive_check;

  begin

    SetAlertLogName("tb_a14_osvvm");
    SetLogEnable(PASSED, FALSE);
    rv.InitSeed(rv'instance_name);
    cov := NewID("runHit x eol");
    AddCross(cov, "runHit x eol", GenBin(0, 1, 2), GenBin(0, 1, 2));

    -- Directed corners.
    drive_check(7, 7, 0, '0', "hit no-eol");
    drive_check(7, 7, 5, '1', "hit eol break");
    drive_check(7, 9, 5, '0', "miss");
    drive_check(0, 0, RC_MOD - 1, '0', "runCnt wrap");        -- 65535 + 1 -> 0

    for i in 1 to N_RAND loop

      ra := rv.RandInt(0, PX_MAX);
      if (rv.RandInt(0, 1) = 0) then
        ix := ra;                                              -- force hit
      else
        ix := rv.RandInt(0, PX_MAX);
      end if;
      rc := rv.RandInt(0, RC_MOD - 1);
      drive_check(ra, ix, rc, bool2bit(rv.RandInt(0, 1) = 1), "rand");
      exit when IsCovered(cov) and i > 100;

    end loop;

    WriteBin(cov);
    AffirmIf(IsCovered(cov), "runHit x eol coverage closed");

    end_of_test("tb_a14_osvvm");
    wait;

  end process stim;

end architecture sim;
