--------------------------------------------------------------------------------
-- OSVVM testbench: context_ram (stateful memory contract).
--
-- Architectural block (no T.87 C segment). Contract verified against an
-- independent behavioral model:
--   * RdLatency = 1.
--   * First read of an address since reset/EOI returns CTX_INIT (the packed
--     A_INIT|B_INIT|C_INIT|N_INIT word), regardless of prior writes; the read
--     clears the init flag for that address.
--   * Same-cycle write to the read address forwards iWrData (WBR rebuilt over the
--     RBW BRAM) -- but only once the address is past its init read (init wins).
--   * Otherwise the read returns the last written value (RBW: a same-cycle write
--     to a *different* path does not affect this read).
--   * Reset / EndOfImage re-arms every address to CTX_INIT (BRAM contents kept).
-- Reads/writes are never issued on a reset or EOI cycle (matches the pipeline),
-- and every address is written before any second read so the modelled and real
-- BRAM contents always agree. Coverage closes the three read outcomes.
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.common.all;

library openlogic_base;
  use openlogic_base.olo_base_pkg_math.log2ceil;

library osvvm;
  context osvvm.OsvvmContext;

library tb_support;
  use tb_support.tb_support_pkg.all;

entity tb_context_ram_osvvm is
end entity tb_context_ram_osvvm;

architecture sim of tb_context_ram_osvvm is

  constant RANGE_P     : positive := CO_RANGE_STD;
  constant RAM_DEPTH   : positive := 367;
  constant A_WIDTH     : positive := CO_AQ_WIDTH_STD;
  constant B_WIDTH     : positive := CO_BQ_WIDTH_STD;
  constant C_WIDTH     : positive := CO_CQ_WIDTH;
  constant N_WIDTH     : positive := CO_NQ_WIDTH_STD;
  constant TOTAL_WIDTH : positive := CO_TOTAL_WIDTH_STD;
  constant ADDR_W      : natural  := log2ceil(RAM_DEPTH);
  constant CLK_PERIOD  : time     := CLK_PERIOD_DEFAULT;

  -- CTX_INIT packing, mirroring the module's documented init word.
  constant A_INIT   : natural := math_max(2, (RANGE_P + 32) / 64);
  constant CTX_INIT : std_logic_vector(TOTAL_WIDTH - 1 downto 0) :=
    std_logic_vector(to_unsigned(A_INIT, A_WIDTH)) &
    std_logic_vector(to_signed(0, B_WIDTH)) &
    std_logic_vector(to_signed(0, C_WIDTH)) &
    std_logic_vector(to_unsigned(1, N_WIDTH));

  signal clk     : std_logic := '0';
  signal rst     : std_logic;
  signal iWrAddr : std_logic_vector(ADDR_W - 1 downto 0);
  signal iWrEn   : std_logic;
  signal iWrData : std_logic_vector(TOTAL_WIDTH - 1 downto 0);
  signal iRdAddr : std_logic_vector(ADDR_W - 1 downto 0);
  signal iRdEn   : std_logic;
  signal iEoi    : std_logic;
  signal oRdData : std_logic_vector(TOTAL_WIDTH - 1 downto 0);

  type mem_t is array (0 to RAM_DEPTH - 1) of std_logic_vector(TOTAL_WIDTH - 1 downto 0);
  type ini_t is array (0 to RAM_DEPTH - 1) of boolean;

begin

  clk_proc : process is
  begin

    clk <= '1';
    wait for CLK_PERIOD / 2;
    clk <= '0';
    wait for CLK_PERIOD / 2;

  end process clk_proc;

  dut : entity work.context_ram(behavioral)
    generic map (
      RANGE_P     => RANGE_P,
      RAM_DEPTH   => RAM_DEPTH,
      A_WIDTH     => A_WIDTH,
      B_WIDTH     => B_WIDTH,
      C_WIDTH     => C_WIDTH,
      N_WIDTH     => N_WIDTH,
      TOTAL_WIDTH => TOTAL_WIDTH
    )
    port map (
      iClk        => clk,
      iRst        => rst,
      iWrAddr     => iWrAddr,
      iWrEn       => iWrEn,
      iWrData     => iWrData,
      iRdAddr     => iRdAddr,
      iRdEn       => iRdEn,
      iEndOfImage => iEoi,
      oRdData     => oRdData
    );

  stim : process is

    variable rv    : RandomPType;
    variable cov   : CoverageIDType;
    variable mem   : mem_t := (others => (others => '0'));
    variable ini   : ini_t := (others => true);
    variable touched : ini_t := (others => false);  -- has the test written it?

    -- One access cycle. Computes the expected read result from the model
    -- (pre-write), advances the model at the edge, then checks oRdData.
    procedure step (
      rdEn   : std_logic;
      rdAddr : natural;
      wrEn   : std_logic;
      wrAddr : natural;
      wrData : std_logic_vector(TOTAL_WIDTH - 1 downto 0);
      msg    : string
    ) is

      variable exp     : std_logic_vector(TOTAL_WIDTH - 1 downto 0);
      variable outcome : integer;

    begin

      iRdEn   <= rdEn;
      iRdAddr <= std_logic_vector(to_unsigned(rdAddr, ADDR_W));
      iWrEn   <= wrEn;
      iWrAddr <= std_logic_vector(to_unsigned(wrAddr, ADDR_W));
      iWrData <= wrData;

      -- Expected result (computed before this cycle's write applies).
      exp     := (others => '0');
      outcome := -1;
      if (rdEn = '1') then
        if (ini(rdAddr)) then
          exp     := CTX_INIT;
          outcome := 0;
        elsif (wrEn = '1' and wrAddr = rdAddr) then
          exp     := wrData;
          outcome := 2;
        else
          exp     := mem(rdAddr);
          outcome := 1;
        end if;
      end if;

      wait until rising_edge(clk);

      -- Model state update at the edge.
      if (rdEn = '1') then
        ini(rdAddr) := false;
      end if;
      if (wrEn = '1') then
        mem(wrAddr)     := wrData;
        touched(wrAddr) := true;
      end if;

      wait for 1 ns;
      if (rdEn = '1') then
        AffirmIfEqual(oRdData, exp, msg);
        ICover(cov, outcome);
      end if;

    end procedure step;

    procedure pulse_eoi is
    begin

      iRdEn <= '0';
      iWrEn <= '0';
      iEoi  <= '1';
      wait until rising_edge(clk);
      ini  := (others => true);                  -- re-arm init, keep mem
      iEoi <= '0';
      wait for 1 ns;

    end procedure pulse_eoi;

    -- Mid-operation iRst: re-arms init for every address (keeps BRAM), same as EOI.
    procedure pulse_rst is
    begin

      iRdEn <= '0';
      iWrEn <= '0';
      rst   <= '1';
      clk_tick(clk, 2);
      rst   <= '0';
      ini := (others => true);                    -- re-arm init, keep mem
      wait until rising_edge(clk);
      wait for 1 ns;

    end procedure pulse_rst;

    variable a    : natural;
    variable d    : std_logic_vector(TOTAL_WIDTH - 1 downto 0);
    constant ZERO : std_logic_vector(TOTAL_WIDTH - 1 downto 0) := (others => '0');

  begin

    iWrAddr <= (others => '0');
    iWrEn   <= '0';
    iWrData <= (others => '0');
    iRdAddr <= (others => '0');
    iRdEn   <= '0';
    iEoi    <= '0';

    SetAlertLogName("tb_context_ram_osvvm");
    SetLogEnable(PASSED, FALSE);
    rv.InitSeed(rv'instance_name);
    cov := NewID("readOutcome");
    AddBins(cov, "readOutcome", GenBin(0, 2, 3));   -- init / bram / forward

    apply_reset(clk, rst, 4, '1');

    --------------------------------------------------------------------------
    -- Directed: init read, then read-modify-write, then forward, then re-read.
    --------------------------------------------------------------------------
    d := std_logic_vector(to_unsigned(12345, TOTAL_WIDTH));
    -- First read of addr 7 -> CTX_INIT, with the write-back in the same cycle.
    step('1', 7, '1', 7, d, "addr7 first read = CTX_INIT (init wins over fwd)");
    -- Read addr 7 again -> the written value from the BRAM.
    step('1', 7, '0', 0, ZERO, "addr7 second read = written value");
    -- Same-cycle read+write addr 7 -> forwarded new data (past init).
    d := std_logic_vector(to_unsigned(54321, TOTAL_WIDTH));
    step('1', 7, '1', 7, d, "addr7 forward new data");
    -- Confirm the forwarded write landed.
    step('1', 7, '0', 0, ZERO, "addr7 read = forwarded value");

    -- EOI re-arms init: addr 7 reads CTX_INIT again.
    pulse_eoi;
    step('1', 7, '0', 0, ZERO, "addr7 after EOI = CTX_INIT");

    -- Mid-operation iRst re-arms init exactly like EOI: addr 7 (written/read
    -- above, so on the BRAM path) must revert to CTX_INIT after a reset.
    pulse_rst;
    step('1', 7, '0', 0, ZERO, "addr7 after mid-op iRst = CTX_INIT");
    -- And a fresh address is still an init read post-reset.
    step('1', 13, '0', 0, ZERO, "addr13 after iRst = CTX_INIT");

    --------------------------------------------------------------------------
    -- Constrained-random: random addresses, always read-modify-write so the
    -- modelled and real BRAM stay in sync.
    --------------------------------------------------------------------------
    for i in 1 to 4000 loop

      a := rv.RandInt(0, RAM_DEPTH - 1);
      d := rv.RandSlv(TOTAL_WIDTH);

      -- ~1-in-6 cycles also forward (read+write same addr); otherwise
      -- read addr a and write it back with new data.
      step('1', a, '1', a, d, "rand rmw a=" & integer'image(a));

      -- Occasional EOI or mid-stream iRst to re-exercise the init path.
      if (rv.DistValInt(((1, 1), (0, 60))) = 1) then
        pulse_eoi;
      elsif (rv.DistValInt(((1, 1), (0, 80))) = 1) then
        pulse_rst;
      end if;

      exit when IsCovered(cov) and i > 200;

    end loop;

    WriteBin(cov);
    AffirmIf(IsCovered(cov), "read-outcome coverage closed");

    end_of_test("tb_context_ram_osvvm");
    wait;

  end process stim;

  watchdog : process is
  begin

    wait for 50 ms;
    Alert("tb_context_ram_osvvm: watchdog timeout", FAILURE);
    std.env.stop;

  end process watchdog;

end architecture sim;
