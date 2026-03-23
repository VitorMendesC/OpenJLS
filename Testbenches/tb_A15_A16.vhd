library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.Common.all;

-- Testbench for A15_A16_encode_run (Mealy FSM).
--
-- Timing model: FSM outputs are combinational from registered state + inputs.
-- Each test cycle:
--   1. Drive inputs
--   2. wait for 1 ns — let combinational outputs settle
--   3. Check outputs  (reflect CURRENT state from last clock + current inputs)
--   4. wait until rising_edge — state registers capture next-state
--
-- The testbench drives A14's combinational outputs directly (iRunHit, iRunCnt,
-- iRunContinue). The top-level RunCnt register — which resets to 0 when
-- oRunContinue='0' — is emulated manually: iRunCnt is set to 1 at the start
-- of each new run (reset-to-0 + A14-increment-to-1).

entity tb_A15_A16 is
end;

architecture bench of tb_A15_A16 is
  shared variable err_count : natural := 0;

  procedure check(cond : boolean; msg : string) is
  begin
    if not cond then
      report msg severity error;
      err_count := err_count + 1;
    end if;
  end procedure;

  constant CLK_PERIOD    : time    := 10 ns;
  constant BITNESS       : natural := 8;
  constant RUN_CNT_WIDTH : natural := 8;

  signal iClk         : std_logic := '0';
  signal iRst         : std_logic := '0';
  signal iEOI         : std_logic := '0';
  signal iRunCnt      : unsigned(RUN_CNT_WIDTH - 1 downto 0) := (others => '0');
  signal iRunHit      : std_logic := '0';
  signal iRunContinue : std_logic := '0';
  signal iModeIsRun   : std_logic := '1';
  signal iIx          : unsigned(BITNESS - 1 downto 0) := (others => '0');
  signal iRa          : unsigned(BITNESS - 1 downto 0) := (others => '0');
  signal iRb          : unsigned(BITNESS - 1 downto 0) := (others => '0');

  signal oRawValid     : std_logic;
  signal oRawSuffixLen : unsigned(4 downto 0);
  signal oRawSuffixVal : unsigned(RUN_CNT_WIDTH - 1 downto 0);
  signal oRIValid      : std_logic;
  signal oRIRunIndex   : unsigned(4 downto 0);
  signal oRIIx         : unsigned(BITNESS - 1 downto 0);
  signal oRIRa         : unsigned(BITNESS - 1 downto 0);
  signal oRIRb         : unsigned(BITNESS - 1 downto 0);

begin
  iClk <= not iClk after CLK_PERIOD / 2;

  dut : entity work.A15_A16_encode_run
    generic map(
      BITNESS       => BITNESS,
      RUN_CNT_WIDTH => RUN_CNT_WIDTH
    )
    port map(
      iClk         => iClk,
      iRst         => iRst,
      iEOI         => iEOI,
      iRunCnt      => iRunCnt,
      iRunHit      => iRunHit,
      iRunContinue => iRunContinue,
      iModeIsRun   => iModeIsRun,
      iIx          => iIx,
      iRa          => iRa,
      iRb          => iRb,
      oRawValid     => oRawValid,
      oRawSuffixLen => oRawSuffixLen,
      oRawSuffixVal => oRawSuffixVal,
      oRIValid      => oRIValid,
      oRIRunIndex   => oRIRunIndex,
      oRIIx         => oRIIx,
      oRIRa         => oRIRa,
      oRIRb         => oRIRb
    );

  stim : process
  begin

    -- -----------------------------------------------------------------------
    -- Test 1: Run interrupted by pixel (A.16 break)
    --
    -- 4 matching pixels. J[0:3]=0 so each pixel hits a boundary (rg=1 each).
    -- After pixel 4: sRUNindex=4, sNextBound=6 (J[4]=1, step=2).
    -- Pixel 5 doesn't match → A.16 break fires simultaneously with oRIValid.
    --
    -- Break residual = iRunCnt(4) - (sNextBound(6) - vStep(2)) = 0
    -- SuffixLen = J[4]+1 = 2, SuffixVal = 0
    -- oRIRunIndex = 4-1 = 3
    -- -----------------------------------------------------------------------
    iRst        <= '1';
    iRunHit     <= '0';
    iRunContinue <= '0';
    iRunCnt     <= (others => '0');
    iEOI        <= '0';
    wait until rising_edge(iClk);
    iRst <= '0';
    -- State: sRUNindex=0, sNextBound=1, sInRun=0

    -- Pixels 1-4: all match, all hit boundaries (J=0 → rg=1 → every pixel is a boundary)
    for cnt in 1 to 4 loop
      iRunHit      <= '1';
      iRunContinue <= '1';
      iRunCnt      <= to_unsigned(cnt, RUN_CNT_WIDTH);
      iIx          <= to_unsigned(10, BITNESS);
      iRa          <= to_unsigned(10, BITNESS);
      iRb          <= to_unsigned(20, BITNESS);
      wait for 1 ns;
      check(oRawValid = '1',
        "T1 pixel " & integer'image(cnt) & ": A.15 boundary '1' expected");
      check(to_integer(oRawSuffixLen) = 1,
        "T1 pixel " & integer'image(cnt) & ": SuffixLen should be 1");
      check(to_integer(oRawSuffixVal) = 1,
        "T1 pixel " & integer'image(cnt) & ": SuffixVal should be 1");
      check(oRIValid = '0',
        "T1 pixel " & integer'image(cnt) & ": oRIValid should be 0 on boundary hit");
      wait until rising_edge(iClk);
    end loop;
    -- State: sRUNindex=4, sNextBound=6, sInRun=1

    -- Pixel 5: break (doesn't match)
    iRunHit      <= '0';
    iRunContinue <= '0';
    iRunCnt      <= to_unsigned(4, RUN_CNT_WIDTH); -- A14 holds on non-match
    iIx          <= to_unsigned(50, BITNESS);      -- breaking pixel
    iRa          <= to_unsigned(10, BITNESS);      -- last run sample
    iRb          <= to_unsigned(20, BITNESS);
    wait for 1 ns;
    check(oRawValid = '1',         "T1 break: oRawValid should be asserted");
    check(to_integer(oRawSuffixLen) = 2, "T1 break: SuffixLen should be J[4]+1=2");
    check(to_integer(oRawSuffixVal) = 0, "T1 break: residual=0");
    check(oRIValid = '1',          "T1 break: oRIValid should be asserted");
    check(to_integer(oRIRunIndex) = 3,   "T1 break: oRIRunIndex should be 4-1=3");
    check(oRIIx = to_unsigned(50, BITNESS), "T1 break: oRIIx should be breaking pixel");
    check(oRIRa = to_unsigned(10, BITNESS), "T1 break: oRIRa should be last run sample");
    check(oRIRb = to_unsigned(20, BITNESS), "T1 break: oRIRb passthrough");
    wait until rising_edge(iClk);

    iModeIsRun <= '0';
    iRunHit    <= '0';
    wait for 5 * CLK_PERIOD;

    -- -----------------------------------------------------------------------
    -- Test 2: Run interrupted by EOL (end of line)
    --
    -- Same 4-pixel setup as Test 1 → state: sRUNindex=4, sNextBound=6.
    -- Pixel 5 matches (iRunContinue=0, end of line). count=5, sNextBound=6
    -- → not a boundary → A.16 EOL '1' residual bit emitted (SuffixLen=1, SuffixVal=1).
    -- No oRIValid: EOL is not a run-interruption, the run just ended gracefully.
    -- -----------------------------------------------------------------------
    iRst        <= '1';
    iModeIsRun  <= '1';
    iRunHit     <= '0';
    iRunContinue <= '0';
    iRunCnt     <= (others => '0');
    wait until rising_edge(iClk);
    iRst <= '0';

    -- Pixels 1-4: same setup (advance state without detailed checks)
    for cnt in 1 to 4 loop
      iRunHit      <= '1';
      iRunContinue <= '1';
      iRunCnt      <= to_unsigned(cnt, RUN_CNT_WIDTH);
      iIx          <= to_unsigned(10, BITNESS);
      iRa          <= to_unsigned(10, BITNESS);
      iRb          <= to_unsigned(20, BITNESS);
      wait for 1 ns;
      wait until rising_edge(iClk);
    end loop;
    -- State: sRUNindex=4, sNextBound=6, sInRun=1

    -- Pixel 5: last pixel of line (matches, but line ends here)
    iRunHit      <= '1';
    iRunContinue <= '0'; -- EOL
    iRunCnt      <= to_unsigned(5, RUN_CNT_WIDTH);
    iIx          <= to_unsigned(10, BITNESS);
    iRa          <= to_unsigned(10, BITNESS);
    iRb          <= to_unsigned(20, BITNESS);
    wait for 1 ns;
    check(oRawValid = '1',
      "T2 EOL: oRawValid should be asserted for residual '1' bit");
    check(to_integer(oRawSuffixLen) = 1,
      "T2 EOL: SuffixLen should be 1 (single '1' bit for EOL residual)");
    check(to_integer(oRawSuffixVal) = 1,
      "T2 EOL: SuffixVal should be 1");
    check(oRIValid = '0',
      "T2 EOL: oRIValid should not be asserted (EOL is not a run interruption)");
    wait until rising_edge(iClk);

    iModeIsRun <= '0';
    iRunHit    <= '0';
    wait for 5 * CLK_PERIOD;

    -- -----------------------------------------------------------------------
    -- Test 3: Run interrupted by EOI (end of image)
    --
    -- 1 matching pixel (hits boundary, oRawValid='1'), then iEOI='1'.
    -- The iEOI gate suppresses all outputs on the EOI cycle and resets state.
    -- Verified by running a fresh pixel after EOI deassertion: it should
    -- behave as if from reset (count=1 hits sNextBound=1 again).
    -- -----------------------------------------------------------------------
    iRst        <= '1';
    iModeIsRun  <= '1';
    iRunHit     <= '0';
    iRunContinue <= '0';
    iRunCnt     <= (others => '0');
    wait until rising_edge(iClk);
    iRst <= '0';

    -- Pixel 1: match, boundary hit
    iRunHit      <= '1';
    iRunContinue <= '1';
    iRunCnt      <= to_unsigned(1, RUN_CNT_WIDTH);
    iIx          <= to_unsigned(10, BITNESS);
    iRa          <= to_unsigned(10, BITNESS);
    iRb          <= to_unsigned(20, BITNESS);
    wait for 1 ns;
    check(oRawValid = '1', "T3 pixel 1: boundary hit before EOI");
    wait until rising_edge(iClk);
    -- State: sRUNindex=1, sNextBound=2, sInRun=1

    -- EOI cycle: outputs must be suppressed regardless of inputs
    iEOI    <= '1';
    iRunHit <= '1';
    iRunCnt <= to_unsigned(2, RUN_CNT_WIDTH);
    wait for 1 ns;
    check(oRawValid = '0', "T3 EOI: oRawValid must be suppressed during EOI");
    check(oRIValid  = '0', "T3 EOI: oRIValid must be suppressed during EOI");
    wait until rising_edge(iClk);
    -- State reset: sRUNindex=0, sNextBound=1, sInRun=0
    iEOI <= '0';

    -- Post-EOI: fresh pixel should behave like the very first pixel of a run
    -- (iRunCnt=1 since top-level resets RunCnt after EOI, A14 increments to 1)
    iRunHit      <= '1';
    iRunContinue <= '1';
    iRunCnt      <= to_unsigned(1, RUN_CNT_WIDTH);
    wait for 1 ns;
    check(oRawValid = '1',
      "T3 post-EOI: state should be reset; count=1 should hit sNextBound=1");
    check(oRIValid = '0',
      "T3 post-EOI: no RI on boundary hit");
    wait until rising_edge(iClk);

    iModeIsRun <= '0';
    iRunHit    <= '0';
    wait for 5 * CLK_PERIOD;

    -- -----------------------------------------------------------------------
    -- Test 4 (bonus): Worst case — 1-pixel runs repeated
    --
    -- A run CAN last exactly 1 pixel: J[0]=0 so rg=1, meaning sNextBound=1
    -- and iRunCnt=1 on the first match → instant boundary hit.
    -- If the next pixel immediately breaks, the run lasted 1 pixel.
    --
    -- Each pair of cycles (state resets to sRUNindex=0 after each break):
    --
    --   Match cycle  : oRawValid=1, SuffixLen=1, SuffixVal=1  (A.15 '1' bit)
    --                  oRIValid=0
    --   Break cycle  : oRawValid=1, SuffixLen=1, SuffixVal=0  (A.16: '0' break, J[1]=0 residual bits)
    --                  oRIValid=1, oRIRunIndex=0
    --
    -- Break residual: iRunCnt(1) - (sNextBound(2) - vStep(1)) = 0
    -- SuffixLen = J[1]+1 = 1,  SuffixVal = 0
    -- oRIRunIndex = sRUNindex(1) - 1 = 0
    -- -----------------------------------------------------------------------
    iRst        <= '1';
    iModeIsRun  <= '1';
    iRunHit     <= '0';
    iRunContinue <= '0';
    iRunCnt     <= (others => '0');
    wait until rising_edge(iClk);
    iRst <= '0';

    for rep in 0 to 4 loop

      -- Match: first (and only) pixel of run hits boundary immediately
      iRunHit      <= '1';
      iRunContinue <= '1';
      iRunCnt      <= to_unsigned(1, RUN_CNT_WIDTH);
      iIx          <= to_unsigned(10, BITNESS);
      iRa          <= to_unsigned(10, BITNESS);
      iRb          <= to_unsigned(20, BITNESS);
      wait for 1 ns;
      check(oRawValid = '1',
        "T4 rep " & integer'image(rep) & " match: A.15 '1' bit expected");
      check(to_integer(oRawSuffixLen) = 1,
        "T4 rep " & integer'image(rep) & " match: SuffixLen=1");
      check(to_integer(oRawSuffixVal) = 1,
        "T4 rep " & integer'image(rep) & " match: SuffixVal=1");
      check(oRIValid = '0',
        "T4 rep " & integer'image(rep) & " match: oRIValid=0");
      wait until rising_edge(iClk);
      -- State: sRUNindex=1, sNextBound=2, sInRun=1

      -- Break: immediate break on next pixel
      iRunHit      <= '0';
      iRunContinue <= '0';
      iRunCnt      <= to_unsigned(1, RUN_CNT_WIDTH); -- A14 holds on non-match
      iIx          <= to_unsigned(50, BITNESS);
      wait for 1 ns;
      check(oRawValid = '1',
        "T4 rep " & integer'image(rep) & " break: oRawValid expected");
      check(to_integer(oRawSuffixLen) = 1,
        "T4 rep " & integer'image(rep) & " break: SuffixLen=J[1]+1=1");
      check(to_integer(oRawSuffixVal) = 0,
        "T4 rep " & integer'image(rep) & " break: residual=0");
      check(oRIValid = '1',
        "T4 rep " & integer'image(rep) & " break: oRIValid expected");
      check(to_integer(oRIRunIndex) = 0,
        "T4 rep " & integer'image(rep) & " break: oRIRunIndex=0");
      wait until rising_edge(iClk);
      -- State: sRUNindex=0, sNextBound=1, sInRun=0
      -- (top-level resets RunCnt to 0 here; next match cycle drives iRunCnt=1)

    end loop;

    -- -----------------------------------------------------------------------
    if err_count > 0 then
      report "tb_A15_A16 RESULT: FAIL (" & integer'image(err_count) & " errors)"
        severity failure;
    else
      report "tb_A15_A16 RESULT: PASS" severity note;
    end if;
    wait for 20 ns;
    finish;
  end process;
end;
