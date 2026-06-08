--------------------------------------------------------------------------------
-- OSVVM testbench: a11_1_golomb_encoder (combinational).
--
-- Limited-length Golomb LG(k, L) per T.87 A.5.3 (regular) and A.22.1 (run
-- interruption, glimit = LIMIT - J[RUNindex] - 1). The module emits the code as
-- (unaryZeros, suffixLen, suffixVal) for the bit packer rather than a bit string.
-- Reference is the T.87 written rule (Docs/Project.md A.11.1/A.11.2):
--   high = MErrval >> k
--   non-escape (high < L-qbpp-1): unary=high, len=k,    val = low k bits
--   escape:                       unary=L-qbpp-1, len=qbpp, val = (MErrval-1) low qbpp bits
-- with L = LIMIT (regular) or glimit (RI). Coverage crosses RI-mode x escape.
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.common.all;

library osvvm;
  context osvvm.OsvvmContext;

library tb_support;
  use tb_support.tb_support_pkg.all;

entity tb_a11_1_osvvm is
end entity tb_a11_1_osvvm;

architecture sim of tb_a11_1_osvvm is

  constant K_WIDTH     : natural := CO_K_WIDTH_STD;
  constant QBPP        : natural := CO_QBPP_STD;
  constant LIMIT       : natural := CO_LIMIT_STD;
  constant UNARY_W     : natural := CO_UNARY_WIDTH_STD;
  constant SUFFIX_W    : natural := CO_SUFFIX_WIDTH_STD;
  constant SUFFIXLEN_W : natural := CO_SUFFIXLEN_WIDTH_STD;
  constant MAPPED_W    : natural := CO_MAPPED_ERROR_VAL_WIDTH_STD;

  -- Valid k domain (encoder assumptions: k <= SUFFIX_W and k <= MAPPED_W).
  constant K_HI        : integer := math_min(QBPP, math_min(SUFFIX_W, MAPPED_W));
  constant MERR_MAX    : integer := (2 ** MAPPED_W) - 1;

  signal sK         : unsigned(K_WIDTH - 1 downto 0);
  signal sMerr      : unsigned(MAPPED_W - 1 downto 0);
  signal sRiMode    : std_logic;
  signal sRunIndex  : unsigned(4 downto 0);
  signal sUnary     : unsigned(UNARY_W - 1 downto 0);
  signal sSuffixLen : unsigned(SUFFIXLEN_W - 1 downto 0);
  signal sSuffixVal : unsigned(SUFFIX_W - 1 downto 0);

  -- L - qbpp - 1 escape threshold for the active mode.
  function threshold_of (
    riMode : std_logic;
    runIdx : integer
  ) return integer is
  begin

    if (riMode = '1') then
      -- glimit = LIMIT - J - 1; threshold = glimit - qbpp - 1.
      return LIMIT - CO_J_TABLE(runIdx) - QBPP - 2;
    else
      return LIMIT - QBPP - 1;
    end if;

  end function threshold_of;

begin

  dut : entity work.a11_1_golomb_encoder(behavioral)
    generic map (
      K_WIDTH                => K_WIDTH,
      QBPP                   => QBPP,
      LIMIT                  => LIMIT,
      UNARY_WIDTH            => UNARY_W,
      SUFFIX_WIDTH           => SUFFIX_W,
      SUFFIXLEN_WIDTH        => SUFFIXLEN_W,
      MAPPED_ERROR_VAL_WIDTH => MAPPED_W
    )
    port map (
      iK              => sK,
      iMappedErrorVal => sMerr,
      iRiMode         => sRiMode,
      iRunIndex       => sRunIndex,
      oUnaryZeros     => sUnary,
      oSuffixLen      => sSuffixLen,
      oSuffixVal      => sSuffixVal
    );

  stim : process is

    variable rv      : RandomPType;
    variable cov     : CovPType;
    variable k       : integer;
    variable merr    : integer;
    variable ridx    : integer;
    constant N_RAND  : natural := 12000;

    procedure drive_check (
      kv   : integer;
      mv   : integer;
      ri   : std_logic;
      rix  : integer;
      msg  : string
    ) is

      variable thr     : integer;
      variable high    : integer;
      variable low     : integer;
      variable expUn   : integer;
      variable expLen  : integer;
      variable expVal  : integer;
      variable escape  : integer;

    begin

      sK        <= to_unsigned(kv, K_WIDTH);
      sMerr     <= to_unsigned(mv, MAPPED_W);
      sRiMode   <= ri;
      sRunIndex <= to_unsigned(rix, 5);
      wait for 1 ns;

      thr  := threshold_of(ri, rix);
      high := mv / (2 ** kv);
      low  := mv mod (2 ** kv);

      if (high < thr) then
        expUn  := high;
        expLen := kv;
        expVal := low;
        escape := 0;
      else
        expUn  := thr;
        expLen := QBPP;
        expVal := (mv - 1) mod (2 ** QBPP);
        escape := 1;
      end if;

      AffirmIfEqual(to_integer(sUnary), expUn, msg & " unary");
      AffirmIfEqual(to_integer(sSuffixLen), expLen, msg & " sufLen");
      AffirmIfEqual(to_integer(sSuffixVal), expVal, msg & " sufVal");

      cov.ICover((std_to_int(ri), escape));

    end procedure drive_check;

  begin

    SetAlertLogName("tb_a11_1_osvvm");
    SetLogEnable(PASSED, FALSE);
    rv.InitSeed(rv'instance_name);

    cov.AddCross("riMode x escape", GenBin(0, 1, 2), GenBin(0, 1, 2));

    -- Directed corners.
    drive_check(0, 0, '0', 0, "reg merr0 k0");           -- non-escape, all minimal
    drive_check(0, MERR_MAX, '0', 0, "reg escape k0");   -- big merr -> escape
    drive_check(K_HI, 1, '0', 0, "reg big-k small");
    drive_check(0, MERR_MAX, '1', 0, "RI escape J=0");
    drive_check(0, MERR_MAX, '1', 31, "RI escape J=max");
    drive_check(2, 5, '1', 10, "RI non-escape");

    -- Random sweep.
    for i in 1 to N_RAND loop

      k    := rv.RandInt(0, K_HI);
      merr := rv.RandInt(0, MERR_MAX);
      ridx := rv.RandInt(0, 31);
      if (rv.RandInt(0, 1) = 0) then
        drive_check(k, merr, '0', ridx, "rand reg");
      else
        drive_check(k, merr, '1', ridx, "rand RI");
      end if;
      exit when cov.IsCovered and i > 400;

    end loop;

    cov.WriteBin;
    AffirmIf(cov.IsCovered, "riMode x escape coverage closed");

    end_of_test("tb_a11_1_osvvm");
    wait;

  end process stim;

end architecture sim;
