--------------------------------------------------------------------------------
-- OSVVM testbench: a23_run_interruption_update (combinational).
--
-- T.87 Code segment A.23 (standard form), transcribed verbatim:
--   if (Errval < 0) Nn += 1;
--   A += (EMErrval + 1 - RItype) >> 1;          -- floor shift
--   if (N == RESET) { A>>=1; N>>=1; Nn>>=1; }
--   N += 1;
-- where EMErrval = 2*abs(Errval) - RItype - map (A.22). The RTL drops map via the
-- Mert Fig.9 equivalence (A += abs(Errval) - RItype). The reference deliberately
-- keeps the *standard* map-dependent form and drives map as a free random input
-- not fed to the DUT, so a passing check also proves the equivalence holds for
-- both map values.
--
-- Every result is representable for T.87-coherent inputs:
--   A_new = A + |Errval| - RItype >= 0: RItype=0 => A+|Errval|>=0; RItype=1 =>
--     |Errval|>=1 (a run-interruption sample has Ix/=Ra, see tb_a22) => A_new>=A>=0.
--   Nn_new <= RESET-1: the invariant N-Nn>=1 holds from init (N=1,Nn=0) and is
--     preserved by the update (N+1, Nn+<=1) and the rescale (floor halving), so
--     input Nn<=N-1 and Nn_new = Nn+1 <= N <= RESET-1 (N=RESET takes the halving).
--   N_new <= RESET+1 < 2^N_WIDTH.
-- The stimulus also sweeps non-coherent inputs (random Nn/N/Errval); any that
-- drive a variable out of range are skipped AND asserted to violate the specific
-- T.87 invariant above, so the skip can never silently swallow a coherent vector.
-- Coverage crosses RESET x Errval-sign x RItype.
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.common.all;

library osvvm;
  context osvvm.OsvvmContext;

library tb_support;
  use tb_support.tb_support_pkg.all;

entity tb_a23_osvvm is
end entity tb_a23_osvvm;

architecture sim of tb_a23_osvvm is

  constant A_WIDTH     : natural := CO_AQ_WIDTH_STD;
  constant N_WIDTH     : natural := CO_NQ_WIDTH_STD;
  constant NN_WIDTH    : natural := CO_NNQ_WIDTH_STD;
  constant ERROR_WIDTH : natural := CO_ERROR_VALUE_WIDTH_STD;
  constant RESET       : natural := CO_RESET_STD;

  constant ERR_LO : integer := -(CO_RANGE_STD / 2);
  constant ERR_HI : integer := CO_RANGE_STD / 2;
  constant A_HI   : integer := (RESET - 1) * CO_RANGE_STD / 2;
  constant NN_MAX : integer := (2 ** NN_WIDTH) - 1;

  signal sErr  : signed(ERROR_WIDTH - 1 downto 0);
  signal sRi   : std_logic;
  signal sAq   : unsigned(A_WIDTH - 1 downto 0);
  signal sNq   : unsigned(N_WIDTH - 1 downto 0);
  signal sNn   : unsigned(NN_WIDTH - 1 downto 0);
  signal sAqO  : unsigned(A_WIDTH - 1 downto 0);
  signal sNqO  : unsigned(N_WIDTH - 1 downto 0);
  signal sNnO  : unsigned(NN_WIDTH - 1 downto 0);

  -- Floor division by 2 (arithmetic >>1), matching the C semantics.
  function fdiv2 (
    x : integer
  ) return integer is
  begin

    if (x >= 0) then
      return x / 2;
    else
      return -(((-x) + 1) / 2);
    end if;

  end function fdiv2;

begin

  dut : entity work.a23_run_interruption_update(behavioral)
    generic map (
      A_WIDTH     => A_WIDTH,
      N_WIDTH     => N_WIDTH,
      NN_WIDTH    => NN_WIDTH,
      ERROR_WIDTH => ERROR_WIDTH,
      RESET       => RESET
    )
    port map (
      iErrVal => sErr,
      iRiType => sRi,
      iAq     => sAq,
      iNq     => sNq,
      iNn     => sNn,
      oAq     => sAqO,
      oNq     => sNqO,
      oNn     => sNnO
    );

  stim : process is

    variable rv      : RandomPType;
    variable cov     : CoverageIDType;
    variable err     : integer;
    variable a       : integer;
    variable n       : integer;
    variable nn      : integer;
    variable ri      : integer;
    variable mp      : integer;
    constant N_RAND  : natural := 12000;

    -- Returns false if the vector is out of the coherent (representable) domain.
    procedure drive_check (
      errv : integer;
      riv  : integer;
      av   : integer;
      nv   : integer;
      nnv  : integer;
      mapv : integer;
      msg  : string
    ) is

      variable rescale : boolean;
      variable emv     : integer;
      variable aAdd    : integer;
      variable aNew    : integer;
      variable nNew    : integer;
      variable nnNew   : integer;
      variable rsc     : integer;
      variable eNeg    : integer;

    begin

      -- Compute the standard reference first; skip non-coherent vectors.
      nnNew := nnv;
      if (errv < 0) then
        nnNew := nnNew + 1;
      end if;
      emv  := 2 * abs(errv) - riv - mapv;
      aAdd := fdiv2(emv + 1 - riv);
      aNew := av + aAdd;

      rescale := (nv = RESET);
      if (rescale) then
        aNew  := aNew / 2;
        nNew  := (nv / 2) + 1;
        nnNew := nnNew / 2;
      else
        nNew := nv + 1;
      end if;

      -- Non-coherent guard: results are representable for any coherent input
      -- (header). A randomly generated vector that lands out of range is skipped,
      -- but only after asserting it violates the specific T.87 invariant -- so the
      -- skip can never silently swallow a coherent vector.
      if (aNew < 0) then
        AffirmIf(riv = 1 and errv = 0,
                 "A_new<0 only when RItype=1 & Errval=0 -- T.87: RItype=1 => Errval/=0");
        return;
      end if;
      if (nnNew > NN_MAX) then
        AffirmIf(nnv >= nv,
                 "Nn overflow only when input Nn>=N -- T.87 invariant N-Nn>=1 forbids it");
        return;
      end if;
      if (nNew > (2 ** N_WIDTH) - 1) then
        AffirmIf(nv > RESET,
                 "N overflow only when input N>RESET -- T.87: N in [1,RESET]");
        return;
      end if;

      sErr <= to_signed(errv, ERROR_WIDTH);
      sRi  <= bool2bit(riv = 1);
      sAq  <= to_unsigned(av, A_WIDTH);
      sNq  <= to_unsigned(nv, N_WIDTH);
      sNn  <= to_unsigned(nnv, NN_WIDTH);
      wait for 1 ns;

      AffirmIfEqual(to_integer(sAqO), aNew, msg & " A");
      AffirmIfEqual(to_integer(sNqO), nNew, msg & " N");
      AffirmIfEqual(to_integer(sNnO), nnNew, msg & " Nn");

      if (rescale) then
        rsc := 1;
      else
        rsc := 0;
      end if;
      if (errv < 0) then
        eNeg := 1;
      else
        eNeg := 0;
      end if;
      ICover(cov, (rsc, eNeg, riv));

    end procedure drive_check;

  begin

    SetAlertLogName("tb_a23_osvvm");
    SetLogEnable(PASSED, FALSE);
    rv.InitSeed(rv'instance_name);

    cov := NewID("rescale x errNeg x RItype");
    AddCross(cov, "rescale x errNeg x RItype", GenBin(0, 1, 2), GenBin(0, 1, 2), GenBin(0, 1, 2));

    -- Directed corners (both map values on the same vector to exercise equivalence).
    drive_check(-5, 0, 100, RESET, 10, 0, "rescale errneg ri0 m0");
    drive_check(-5, 0, 100, RESET, 10, 1, "rescale errneg ri0 m1");
    drive_check(5, 1, 100, 10, 4, 0, "errpos ri1 m0");
    drive_check(5, 1, 100, 10, 4, 1, "errpos ri1 m1");
    drive_check(0, 1, 50, 5, 0, 0, "err0 ri1");

    for i in 1 to N_RAND loop

      err := rv.RandInt(ERR_LO, ERR_HI);
      ri  := rv.RandInt(0, 1);
      a   := rv.RandInt(0, A_HI);
      nn  := rv.RandInt(0, NN_MAX);
      mp  := rv.RandInt(0, 1);
      if (rv.RandInt(0, 2) = 0) then
        n := RESET;                                  -- bias the rescale path
      else
        n := rv.RandInt(1, RESET);
      end if;
      drive_check(err, ri, a, n, nn, mp, "rand");
      exit when IsCovered(cov) and i > 600;

    end loop;

    WriteBin(cov);
    AffirmIf(IsCovered(cov), "rescale x errNeg x RItype coverage closed");

    end_of_test("tb_a23_osvvm");
    wait;

  end process stim;

end architecture sim;
