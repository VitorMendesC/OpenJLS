--------------------------------------------------------------------------------
-- OSVVM testbench: a12_variables_update (combinational).
--
-- T.87 Code segment A.12 with NEAR=0 (2*NEAR+1 = 1):
--   B += Errval; A += abs(Errval);
--   if (N == RESET) { A>>=1; B = (B>=0)? B>>1 : -((1-B)>>1); N>>=1; }
--   N += 1;
-- Reference follows that order verbatim; the negative-B halving uses the C
-- -((1-B)>>1) form (not the RTL arithmetic shift) so the two stay independent.
-- Coverage crosses the RESET rescale with the post-add sign of B.
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.common.all;

library osvvm;
  context osvvm.OsvvmContext;

library tb_support;
  use tb_support.tb_support_pkg.all;

entity tb_a12_osvvm is
end entity tb_a12_osvvm;

architecture sim of tb_a12_osvvm is

  constant ERROR_WIDTH : natural := CO_ERROR_VALUE_WIDTH_STD;
  constant A_WIDTH     : natural := CO_AQ_WIDTH_STD;
  constant B_WIDTH     : natural := CO_BQ_WIDTH_STD;
  constant N_WIDTH     : natural := CO_NQ_WIDTH_STD;
  constant RESET       : natural := CO_RESET_STD;

  -- Non-overflowing operating ranges (post-A.9 error, T.87 variable bounds).
  constant ERR_LO : integer := -(CO_RANGE_STD / 2);
  constant ERR_HI : integer := CO_RANGE_STD / 2;
  constant A_HI   : integer := (RESET - 1) * CO_RANGE_STD / 2;
  constant B_LIM  : integer := RESET - 1;

  signal sErr  : signed(ERROR_WIDTH - 1 downto 0);
  signal sAq   : unsigned(A_WIDTH - 1 downto 0);
  signal sBq   : signed(B_WIDTH - 1 downto 0);
  signal sNq   : unsigned(N_WIDTH - 1 downto 0);
  signal sAqO  : unsigned(A_WIDTH - 1 downto 0);
  signal sBqO  : signed(B_WIDTH - 1 downto 0);
  signal sNqO  : unsigned(N_WIDTH - 1 downto 0);

begin

  dut : entity work.a12_variables_update(rtl)
    generic map (
      ERROR_WIDTH => ERROR_WIDTH,
      A_WIDTH     => A_WIDTH,
      B_WIDTH     => B_WIDTH,
      N_WIDTH     => N_WIDTH,
      RESET       => RESET
    )
    port map (
      iErrorVal => sErr,
      iAq       => sAq,
      iBq       => sBq,
      iNq       => sNq,
      oAq       => sAqO,
      oBq       => sBqO,
      oNq       => sNqO
    );

  stim : process is

    variable rv      : RandomPType;
    variable cov     : CovPType;
    constant N_RAND  : natural := 8000;

    procedure drive_check (
      err : integer;
      a   : integer;
      b   : integer;
      n   : integer;
      msg : string
    ) is

      variable rescale : boolean;
      variable aNew    : integer;
      variable bSum    : integer;
      variable bNew    : integer;
      variable nNew    : integer;
      variable rsc     : integer;
      variable bSgn    : integer;

    begin

      sErr <= to_signed(err, ERROR_WIDTH);
      sAq  <= to_unsigned(a, A_WIDTH);
      sBq  <= to_signed(b, B_WIDTH);
      sNq  <= to_unsigned(n, N_WIDTH);
      wait for 1 ns;

      rescale := (n = RESET);
      aNew    := a + abs(err);
      bSum    := b + err;

      if (rescale) then
        aNew := aNew / 2;
        if (bSum >= 0) then
          bNew := bSum / 2;
        else
          bNew := -((1 - bSum) / 2);
        end if;
        nNew := (n / 2) + 1;
      else
        bNew := bSum;
        nNew := n + 1;
      end if;

      AffirmIfEqual(to_integer(sAqO), aNew, msg & " A");
      AffirmIfEqual(to_integer(sBqO), bNew, msg & " B");
      AffirmIfEqual(to_integer(sNqO), nNew, msg & " N");

      if (rescale) then
        rsc := 1;
      else
        rsc := 0;
      end if;
      if (bSum >= 0) then
        bSgn := 0;
      else
        bSgn := 1;
      end if;
      cov.ICover((rsc, bSgn));

    end procedure drive_check;

  begin

    SetAlertLogName("tb_a12_osvvm");
    SetLogEnable(PASSED, FALSE);
    rv.InitSeed(rv'instance_name);

    cov.AddCross("rescale x bSumSign", GenBin(0, 1, 2), GenBin(0, 1, 2));

    -- Directed corners.
    drive_check(0, 0, 0, 1, "min no-rescale");
    drive_check(ERR_HI, A_HI, B_LIM, RESET, "rescale pos B");
    drive_check(ERR_LO, A_HI, -B_LIM, RESET, "rescale neg B");
    drive_check(-1, 5, -1, RESET, "rescale neg odd B");

    -- Random sweep (N biased to RESET for the rescale path).
    for i in 1 to N_RAND loop

      if (rv.RandInt(0, 2) = 0) then
        drive_check(rv.RandInt(ERR_LO, ERR_HI), rv.RandInt(0, A_HI),
                    rv.RandInt(-B_LIM, B_LIM), RESET, "rand rescale");
      else
        drive_check(rv.RandInt(ERR_LO, ERR_HI), rv.RandInt(0, A_HI),
                    rv.RandInt(-B_LIM, B_LIM), rv.RandInt(1, RESET), "rand");
      end if;
      exit when cov.IsCovered and i > 300;

    end loop;

    cov.WriteBin;
    AffirmIf(cov.IsCovered, "rescale x bSign coverage closed");

    end_of_test("tb_a12_osvvm");
    wait;

  end process stim;

end architecture sim;
