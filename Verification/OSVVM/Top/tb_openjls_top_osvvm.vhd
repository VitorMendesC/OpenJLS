--------------------------------------------------------------------------------
-- OSVVM top-level control-plane stress testbench: openjls_top.
--
-- Per the verification plan, the golden suite owns payload correctness; OSVVM
-- here proves the *envelope* survives stress. The T.87 Annex H.3 image (4x4,
-- 8-bit, NEAR=0) has a known 57-byte output, used as the invariance oracle:
--   * downstream backpressure (random iReady de-assertion) -> output byte-identical
--   * upstream input stalls (random iValid gaps)           -> output byte-identical
--   * mid-image reset injection                            -> the next image still
--                                                             encodes correctly
-- The output must equal the H.3 golden bytes under every stress combination.
-- Coverage closes backpressure, input-stall, and reset-recovery usage.
--
-- Restores the output-backpressure / stall-recovery coverage the golden TB
-- dropped (project-backpressure-coverage-gap).
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

entity tb_openjls_top_osvvm is
end entity tb_openjls_top_osvvm;

architecture sim of tb_openjls_top_osvvm is

  constant CLK_PERIOD     : time     := CLK_PERIOD_DEFAULT;
  constant BITNESS        : natural  := 8;
  constant MAX_W          : positive := 4096;
  constant MAX_H          : positive := 4096;
  -- Mirrors openjls_top's default OUT_WIDTH derivation for this BITNESS.
  constant OUT_WIDTH      : natural  := math_ceil_div(4 * BITNESS + 4 * BITNESS / 8 + 7, 8) * 8 + 8;
  constant BYTES_PER_WORD : natural  := OUT_WIDTH / 8;

  constant IMG_W : natural := 4;
  constant IMG_H : natural := 4;

  type pixel_array_t is array (natural range <>) of natural;

  constant PIXELS : pixel_array_t(0 to 15) :=
    (0, 0, 90, 74, 68, 50, 43, 205, 64, 145, 145, 145, 100, 145, 145, 145);

  type byte_array_t is array (natural range <>) of std_logic_vector(7 downto 0);

  -- T.87 Annex H.3 golden output: 25-byte header + 30-byte payload + FF D9.
  constant EXPECTED : byte_array_t(0 to 56) :=
    (x"FF", x"D8", x"FF", x"F7", x"00", x"0B", x"08", x"00", x"04", x"00", x"04",
     x"01", x"01", x"11", x"00", x"FF", x"DA", x"00", x"08", x"01", x"01", x"00",
     x"00", x"00", x"00",
     x"C0", x"00", x"00", x"6C", x"80", x"20", x"8E", x"01", x"C0", x"00", x"00",
     x"57", x"40", x"00", x"00", x"6E", x"E6", x"00", x"00", x"01", x"BC", x"18",
     x"00", x"00", x"05", x"D8", x"00", x"00", x"91", x"60",
     x"FF", x"D9");
  constant EXP_BYTES : natural := EXPECTED'length;

  signal clk     : std_logic := '0';
  signal rst     : std_logic;
  signal iValid  : std_logic;
  signal iPixel  : std_logic_vector(BITNESS - 1 downto 0);
  signal oReady  : std_logic;
  signal iWidth  : std_logic_vector(log2ceil(MAX_W + 1) - 1 downto 0);
  signal iHeight : std_logic_vector(log2ceil(MAX_H + 1) - 1 downto 0);
  signal oData   : std_logic_vector(OUT_WIDTH - 1 downto 0);
  signal oValid  : std_logic;
  signal oKeep   : std_logic_vector(OUT_WIDTH / 8 - 1 downto 0);
  signal oLast   : std_logic;
  signal iReady  : std_logic;

  -- Downstream backpressure mode: '0' always ready, '1' random.
  signal sBpMode : std_logic := '0';

  shared variable collected      : byte_array_t(0 to 8191);
  shared variable collectedCount : natural;
  shared variable lastCount      : natural;

begin

  clk_proc : process is
  begin

    clk <= '0';
    wait for CLK_PERIOD / 2;
    clk <= '1';
    wait for CLK_PERIOD / 2;

  end process clk_proc;

  iWidth  <= std_logic_vector(to_unsigned(IMG_W, iWidth'length));
  iHeight <= std_logic_vector(to_unsigned(IMG_H, iHeight'length));

  dut : entity work.openjls_top(rtl)
    generic map (
      BITNESS          => BITNESS,
      MAX_IMAGE_WIDTH  => MAX_W,
      MAX_IMAGE_HEIGHT => MAX_H,
      OUT_WIDTH        => OUT_WIDTH
    )
    port map (
      iClk         => clk,
      iRst         => rst,
      iValid       => iValid,
      iPixel       => iPixel,
      oReady       => oReady,
      iImageWidth  => iWidth,
      iImageHeight => iHeight,
      oData        => oData,
      oValid       => oValid,
      oKeep        => oKeep,
      oLast        => oLast,
      iReady       => iReady
    );

  -----------------------------------------------------------------------------
  -- Output collector (oKeep bytes, MSB-first, on the AXI handshake).
  -----------------------------------------------------------------------------
  collect_proc : process (clk) is
  begin

    if rising_edge(clk) then
      if (rst = '1') then
        collectedCount := 0;
        lastCount      := 0;
      elsif (oValid = '1' and iReady = '1') then

        for i in 0 to BYTES_PER_WORD - 1 loop

          if (oKeep(BYTES_PER_WORD - 1 - i) = '1') then
            if (collectedCount < collected'length) then
              collected(collectedCount) := oData(OUT_WIDTH - 1 - i * 8 downto OUT_WIDTH - (i + 1) * 8);
            end if;
            collectedCount := collectedCount + 1;
          end if;

        end loop;

        if (oLast = '1') then
          lastCount := lastCount + 1;
        end if;
      end if;
    end if;

  end process collect_proc;

  -----------------------------------------------------------------------------
  -- Downstream backpressure driver.
  -----------------------------------------------------------------------------
  ready_proc : process is

    variable rv : RandomPType;

  begin

    rv.InitSeed("ready");
    iReady <= '1';

    loop

      wait until rising_edge(clk);
      if (sBpMode = '0') then
        iReady <= '1';
      else
        -- ~33% ready, with occasional ready bursts to guarantee drain.
        iReady <= bool2bit(rv.DistValInt(((1, 1), (0, 2))) = 1);
      end if;

    end loop;

  end process ready_proc;

  -----------------------------------------------------------------------------
  -- Stimulus.
  -----------------------------------------------------------------------------
  stim : process is

    variable rv      : RandomPType;
    variable covBp   : CovPType;
    variable covSt   : CovPType;
    variable covRst  : CovPType;
    variable base    : natural;
    variable baseL   : natural;

    procedure do_reset is
    begin

      rst    <= '1';
      iValid <= '0';
      iPixel <= (others => '0');
      clk_tick(clk, 4);
      rst <= '0';
      wait until rising_edge(clk);

      while (oReady /= '1') loop

        wait until rising_edge(clk);

      end loop;

    end procedure do_reset;

    -- Feed the H.3 image; stall inserts random iValid gaps; count = how many
    -- pixels to feed (full image unless truncated for reset injection).
    procedure feed (
      stall : boolean;
      count : natural
    ) is
    begin

      for i in 0 to count - 1 loop

        if (stall) then
          while (rv.DistValInt(((1, 1), (0, 3))) = 1) loop

            iValid <= '0';
            wait until rising_edge(clk);

          end loop;
        end if;

        iPixel <= std_logic_vector(to_unsigned(PIXELS(i), BITNESS));
        iValid <= '1';
        wait until oReady = '1' and rising_edge(clk);

      end loop;

      iValid <= '0';

    end procedure feed;

    procedure wait_one_image is
    begin

      for i in 0 to 99999 loop

        exit when lastCount >= baseL + 1;
        wait until rising_edge(clk);

      end loop;

    end procedure wait_one_image;

    -- Encode one full image and assert the output equals the H.3 golden bytes.
    procedure run_check (
      bp    : std_logic;
      stall : boolean;
      msg   : string
    ) is
    begin

      base    := collectedCount;
      baseL   := lastCount;
      sBpMode <= bp;
      feed(stall, PIXELS'length);
      wait_one_image;

      AffirmIfEqual(collectedCount - base, EXP_BYTES, msg & " byte count");
      for i in 0 to EXP_BYTES - 1 loop

        if (base + i < collectedCount) then
          AffirmIfEqual(collected(base + i), EXPECTED(i),
                        msg & " byte " & integer'image(i));
        end if;

      end loop;

      covBp.ICover(std_to_int(bp));
      covSt.ICover(boolean'pos(stall));

    end procedure run_check;

  begin

    rst     <= '1';
    iValid  <= '0';
    iPixel  <= (others => '0');
    sBpMode <= '0';

    SetAlertLogName("tb_openjls_top_osvvm");
    SetLogEnable(PASSED, FALSE);
    rv.InitSeed(rv'instance_name);
    covBp.AddBins("backpressure", GenBin(0, 1, 2));
    covSt.AddBins("inputStall", GenBin(0, 1, 2));
    covRst.AddBins("resetRecovery", GenBin(0, 0));

    do_reset;

    --------------------------------------------------------------------------
    -- Directed: each stress axis, clean baseline first.
    --------------------------------------------------------------------------
    run_check('0', false, "baseline");
    run_check('1', false, "downstream backpressure");
    run_check('0', true, "input stall");
    run_check('1', true, "backpressure + stall");

    --------------------------------------------------------------------------
    -- Mid-image reset injection, then a clean image must still be correct.
    --------------------------------------------------------------------------
    sBpMode <= '0';
    feed(false, 8);                 -- partial image (8 of 16 pixels)
    do_reset;                       -- abort mid-image
    run_check('0', false, "post-reset recovery");
    covRst.ICover(0);

    -- Reset injection while under backpressure, then recover.
    sBpMode <= '1';
    feed(true, 6);
    do_reset;
    run_check('1', true, "post-reset recovery under stress");

    --------------------------------------------------------------------------
    -- Randomized stress sweep.
    --------------------------------------------------------------------------
    for r in 1 to 40 loop

      -- Occasional mid-image reset injection.
      if (rv.DistValInt(((1, 1), (0, 5))) = 1) then
        sBpMode <= bool2bit(rv.RandInt(0, 1) = 1);
        feed(rv.RandInt(0, 1) = 1, rv.RandInt(1, PIXELS'length - 1));
        do_reset;
      end if;

      run_check(bool2bit(rv.RandInt(0, 1) = 1), rv.RandInt(0, 1) = 1,
                "rand r=" & integer'image(r));

      exit when covBp.IsCovered and covSt.IsCovered and r > 8;

    end loop;

    covBp.WriteBin;
    covSt.WriteBin;
    covRst.WriteBin;
    AffirmIf(covBp.IsCovered, "backpressure coverage closed");
    AffirmIf(covSt.IsCovered, "input-stall coverage closed");
    AffirmIf(covRst.IsCovered, "reset-recovery coverage closed");

    end_of_test("tb_openjls_top_osvvm");
    wait;

  end process stim;

  watchdog : process is
  begin

    wait for 200 ms;
    Alert("tb_openjls_top_osvvm: watchdog timeout", FAILURE);
    std.env.stop;

  end process watchdog;

end architecture sim;
