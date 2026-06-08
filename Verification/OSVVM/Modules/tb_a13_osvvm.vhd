--------------------------------------------------------------------------------
-- OSVVM testbench: a13_update_bias (combinational).
--
-- T.87 Code segment A.13, transcribed verbatim (note the inner re-test of B
-- against -N after the adjust):
--   if (B <= -N) { B += N; if (C>MIN_C) C--; if (B <= -N) B = -N+1; }
--   else if (B > 0) { B -= N; if (C<MAX_C) C++; if (B > 0) B = 0; }
-- Coverage closes the three branches and both inner-clamp outcomes.
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.common.all;

library osvvm;
  context osvvm.OsvvmContext;

library tb_support;
  use tb_support.tb_support_pkg.all;

entity tb_a13_osvvm is
end entity tb_a13_osvvm;

architecture sim of tb_a13_osvvm is

  constant B_WIDTH : natural := CO_BQ_WIDTH_STD;
  constant N_WIDTH : natural := CO_NQ_WIDTH_STD;
  constant C_WIDTH : natural := CO_CQ_WIDTH;
  constant MIN_C   : integer := CO_MIN_CQ;
  constant MAX_C   : integer := CO_MAX_CQ;
  constant RESET   : natural := CO_RESET_STD;

  signal sBq  : signed(B_WIDTH - 1 downto 0);
  signal sNq  : unsigned(N_WIDTH - 1 downto 0);
  signal sCq  : signed(C_WIDTH - 1 downto 0);
  signal sBqO : signed(B_WIDTH - 1 downto 0);
  signal sCqO : signed(C_WIDTH - 1 downto 0);

begin

  dut : entity work.a13_update_bias(rtl)
    generic map (
      B_WIDTH => B_WIDTH,
      N_WIDTH => N_WIDTH,
      C_WIDTH => C_WIDTH,
      MIN_C   => MIN_C,
      MAX_C   => MAX_C
    )
    port map (
      iBq => sBq,
      iNq => sNq,
      iCq => sCq,
      oBq => sBqO,
      oCq => sCqO
    );

  stim : process is

    variable rv      : RandomPType;
    variable cov     : CovPType;
    constant N_RAND  : natural := 8000;

    -- event: 0 neg-noclamp, 1 neg-clamp, 2 pos-noclamp, 3 pos-clamp, 4 none.
    procedure drive_check (
      b   : integer;
      n   : integer;
      c   : integer;
      msg : string
    ) is

      variable bNew : integer;
      variable cNew : integer;
      variable ev   : integer;

    begin

      sBq <= to_signed(b, B_WIDTH);
      sNq <= to_unsigned(n, N_WIDTH);
      sCq <= to_signed(c, C_WIDTH);
      wait for 1 ns;

      bNew := b;
      cNew := c;
      ev   := 4;

      if (b <= -n) then
        bNew := b + n;
        if (c > MIN_C) then
          cNew := c - 1;
        end if;
        if (bNew <= -n) then
          bNew := -n + 1;
          ev   := 1;
        else
          ev := 0;
        end if;
      elsif (b > 0) then
        bNew := b - n;
        if (c < MAX_C) then
          cNew := c + 1;
        end if;
        if (bNew > 0) then
          bNew := 0;
          ev   := 3;
        else
          ev := 2;
        end if;
      end if;

      AffirmIfEqual(to_integer(sBqO), bNew, msg & " B");
      AffirmIfEqual(to_integer(sCqO), cNew, msg & " C");
      cov.ICover(ev);

    end procedure drive_check;

  begin

    SetAlertLogName("tb_a13_osvvm");
    SetLogEnable(PASSED, FALSE);
    rv.InitSeed(rv'instance_name);

    cov.AddBins("event", GenBin(0, 4, 5));

    -- Directed: one per event.
    drive_check(-100, 10, 0, "neg branch, big B (clamp)");   -- B=-100<=-10; B+N=-90<=-10 -> clamp
    drive_check(-12, 10, 0, "neg branch no clamp");          -- B=-12<=-10; B+N=-2 >-10 -> no clamp
    drive_check(50, 10, 0, "pos branch clamp");              -- B=50>0; B-N=40>0 -> clamp 0
    drive_check(5, 10, 0, "pos branch no clamp");            -- B=5>0; B-N=-5 <=0 -> no clamp
    drive_check(0, 10, 0, "none branch");                    -- B=0, not <=-10, not >0
    drive_check(-100, 10, MIN_C, "neg branch C at MIN");     -- C not decremented
    drive_check(50, 10, MAX_C, "pos branch C at MAX");       -- C not incremented

    -- Random sweep (N in [1,RESET]; B biased to the two active branches).
    for i in 1 to N_RAND loop

      if (rv.RandInt(0, 1) = 0) then
        drive_check(rv.RandInt(-(2 * RESET), 2 * RESET), rv.RandInt(1, RESET),
                    rv.RandInt(MIN_C, MAX_C), "rand small");
      else
        drive_check(rv.RandInt(-4096, 4095), rv.RandInt(1, RESET),
                    rv.RandInt(MIN_C, MAX_C), "rand wide");
      end if;
      exit when cov.IsCovered and i > 300;

    end loop;

    cov.WriteBin;
    AffirmIf(cov.IsCovered, "branch/clamp coverage closed");

    end_of_test("tb_a13_osvvm");
    wait;

  end process stim;

end architecture sim;
