library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library osvvm;
  context osvvm.OsvvmContext;

package tb_support_pkg is

  constant CLK_PERIOD_DEFAULT : time := 10 ns;

  -- T.87 Annex H.3 conformance image (4x4, 8-bit, NEAR=0) and its known-good
  -- 57-byte JPEG-LS stream. Shared self-contained oracle for the Xilinx wrapper
  -- TBs; the same vectors live in Top/tb_openjls_top_osvvm.vhd (the module that
  -- owns payload correctness). Held as integer_vector so the OSVVM AxiStream
  -- burst API (PushBurst / CheckBurst) consumes them directly.
  constant H3_WIDTH    : natural := 4;
  constant H3_HEIGHT   : natural := 4;
  constant H3_BITNESS  : natural := 8;

  constant H3_PIXELS   : integer_vector(0 to 15) :=
    (0, 0, 90, 74, 68, 50, 43, 205, 64, 145, 145, 145, 100, 145, 145, 145);

  constant H3_EXPECTED : integer_vector(0 to 56) :=
    (16#FF#, 16#D8#, 16#FF#, 16#F7#, 16#00#, 16#0B#, 16#08#, 16#00#, 16#04#, 16#00#, 16#04#,
     16#01#, 16#01#, 16#11#, 16#00#, 16#FF#, 16#DA#, 16#00#, 16#08#, 16#01#, 16#01#, 16#00#,
     16#00#, 16#00#, 16#00#,
     16#C0#, 16#00#, 16#00#, 16#6C#, 16#80#, 16#20#, 16#8E#, 16#01#, 16#C0#, 16#00#, 16#00#,
     16#57#, 16#40#, 16#00#, 16#00#, 16#6E#, 16#E6#, 16#00#, 16#00#, 16#01#, 16#BC#, 16#18#,
     16#00#, 16#00#, 16#05#, 16#D8#, 16#00#, 16#00#, 16#91#, 16#60#,
     16#FF#, 16#D9#);

  -- 12-bit companion image (4x4, NEAR=0) for the two-byte pixel lane of the
  -- Xilinx stream wrapper (BITNESS 9..16 -> 16-bit TDATA). Golden minted with
  -- the vendored CharLS encoder after the byte-exact T16E0.JLS trust gate
  -- (same flow as "Verification/Golden model/build_run.sh"):
  --   charls-cli encode b12.pgm b12.jls    # P5, 4x4, maxval 4095, big-endian
  -- Pixel values span the full 12-bit range (0/4095), sit above the 8-bit
  -- ceiling (so a dropped upper byte cannot go unnoticed) and include a flat
  -- run to enter run mode.
  constant B12_WIDTH   : natural := 4;
  constant B12_HEIGHT  : natural := 4;
  constant B12_BITNESS : natural := 12;

  constant B12_PIXELS  : integer_vector(0 to 15) :=
    (0, 4095, 2048, 1024, 300, 300, 300, 300, 256, 511, 2047, 3000, 100, 100, 2048, 4000);

  constant B12_EXPECTED : integer_vector(0 to 62) :=
    (16#FF#, 16#D8#, 16#FF#, 16#F7#, 16#00#, 16#0B#, 16#0C#, 16#00#, 16#04#, 16#00#, 16#04#,
     16#01#, 16#01#, 16#11#, 16#00#, 16#FF#, 16#DA#, 16#00#, 16#08#, 16#01#, 16#01#, 16#00#,
     16#00#, 16#00#, 16#00#,
     16#A0#, 16#00#, 16#00#, 16#00#, 16#00#, 16#0F#, 16#FE#, 16#FF#, 16#78#, 16#01#, 16#60#,
     16#01#, 16#66#, 16#04#, 16#03#, 16#70#, 16#1F#, 16#80#, 16#00#, 16#00#, 16#00#, 16#06#,
     16#FF#, 16#5E#, 16#EA#, 16#1D#, 16#C0#, 16#7D#, 16#00#, 16#0F#, 16#00#, 16#00#, 16#00#,
     16#00#, 16#28#, 16#00#, 16#FF#, 16#D9#);

  procedure clk_tick (
    signal   clk    : in    std_logic;
    constant cycles : in    natural := 1
  );

  procedure apply_reset (
    signal   clk    : in    std_logic;
    signal   rst    : out   std_logic;
    constant cycles : in    natural := 4;
    constant active : in    std_logic := '1'
  );

  procedure end_of_test (
    constant test_name : in string
  );

end package tb_support_pkg;

package body tb_support_pkg is

  procedure clk_tick (
    signal   clk    : in    std_logic;
    constant cycles : in    natural := 1
  ) is
  begin
    for i in 1 to cycles loop
      wait until rising_edge(clk);
    end loop;
  end procedure;

  procedure apply_reset (
    signal   clk    : in    std_logic;
    signal   rst    : out   std_logic;
    constant cycles : in    natural := 4;
    constant active : in    std_logic := '1'
  ) is
  begin
    rst <= active;
    for i in 1 to cycles loop
      wait until rising_edge(clk);
    end loop;
    rst <= not active;
    wait until rising_edge(clk);
  end procedure;

  procedure end_of_test (
    constant test_name : in string
  ) is
    variable errors : integer;
  begin
    -- EndOfTestReports = ReportAlerts + YAML emission (alerts, functional
    -- coverage, scoreboards) consumed by the OSVVM script flow's HTML reports.
    errors := EndOfTestReports;
    if errors = 0 then
      report test_name & ": PASS" severity note;
    else
      report test_name & ": FAIL" severity failure;
    end if;
    std.env.stop;
  end procedure;

end package body tb_support_pkg;
