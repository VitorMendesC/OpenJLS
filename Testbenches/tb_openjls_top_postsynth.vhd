----------------------------------------------------------------------------------
-- Engineer:    Vitor Mendes Camilo
--
-- Testbench: tb_openjls_top_postsynth
--
-- Post-synthesis variant of tb_openjls_top. Vivado bakes generics into the
-- synthesized netlist, so the DUT instantiation drops the generic map and
-- the TB-local constants below MUST match the values used at synthesis time.
-- Adjust the four constants if synth was run with non-default values.
----------------------------------------------------------------------------------
use work.Common.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.env.all;

library openlogic_base;
use openlogic_base.olo_base_pkg_math.log2ceil;

entity tb_openjls_top_postsynth is
end;

architecture bench of tb_openjls_top_postsynth is

  constant PRINT_BYTES : boolean := false;

  -- Test configuration. Must match synthesis-time generic values.
  constant CLK_PERIOD       : time     := 10 ns;
  constant BITNESS          : natural  := 8;
  constant MAX_IMAGE_WIDTH  : positive := 4096;
  constant MAX_IMAGE_HEIGHT : positive := 4096;
  constant OUT_WIDTH        : natural  := 56;
  constant BYTES_PER_WORD   : natural  := OUT_WIDTH / 8;

  constant IMG_W : natural := 4;
  constant IMG_H : natural := 4;

  -- T.87 Annex H.3 pixel set (raster order, 4x4, 8-bit)
  type pixel_array_t is array (natural range <>) of natural;
  constant PIXELS : pixel_array_t(0 to 15) := (
  0, 0, 90, 74,
  68, 50, 43, 205,
  64, 145, 145, 145,
  100, 145, 145, 145
  );

  -- Expected 57-byte output
  type byte_array_t is array (natural range <>) of std_logic_vector(7 downto 0);
  constant EXPECTED : byte_array_t(0 to 56) := (
  x"FF", x"D8",
  x"FF", x"F7", x"00", x"0B", x"08", x"00", x"04", x"00", x"04",
  x"01", x"01", x"11", x"00",
  x"FF", x"DA", x"00", x"08", x"01", x"01", x"00", x"00", x"00", x"00",
  x"C0", x"00", x"00", x"6C",
  x"80", x"20", x"8E", x"01",
  x"C0", x"00", x"00", x"57",
  x"40", x"00", x"00", x"6E",
  x"E6", x"00", x"00", x"01",
  x"BC", x"18", x"00", x"00",
  x"05", x"D8", x"00", x"00",
  x"91", x"60",
  x"FF", x"D9"
  );
  constant EXPECTED_BYTES : natural := EXPECTED'length;

  -- DUT ports
  signal iClk         : std_logic                              := '0';
  signal iRst         : std_logic                              := '1';
  signal iValid       : std_logic                              := '0';
  signal iPixel       : std_logic_vector(BITNESS - 1 downto 0) := (others => '0');
  signal oReady       : std_logic;
  signal iImageWidth  : std_logic_vector(log2ceil(MAX_IMAGE_WIDTH + 1) - 1 downto 0);
  signal iImageHeight : std_logic_vector(log2ceil(MAX_IMAGE_HEIGHT + 1) - 1 downto 0);
  signal oData        : std_logic_vector(OUT_WIDTH - 1 downto 0);
  signal oValid       : std_logic;
  signal oKeep        : std_logic_vector(OUT_WIDTH / 8 - 1 downto 0);
  signal oLast        : std_logic;
  signal iReady       : std_logic := '1';

  signal sPulseIReady : std_logic := '0';

  shared variable collected       : byte_array_t(0 to 511) := (others => (others => '0'));
  shared variable collected_count : natural                := 0;
  shared variable last_count      : natural                := 0;

  shared variable err_count : natural := 0;

  procedure check(cond : boolean; msg : string) is
  begin
    if not cond then
      report msg severity error;
      err_count := err_count + 1;
    end if;
  end procedure;

  function hex2(v : std_logic_vector(7 downto 0)) return string is
    constant HEX    : string(1 to 16) := "0123456789ABCDEF";
    variable r      : string(1 to 2);
  begin
    r(1) := HEX(to_integer(unsigned(v(7 downto 4))) + 1);
    r(2) := HEX(to_integer(unsigned(v(3 downto 0))) + 1);
    return r;
  end function;

begin

  iClk <= not iClk after CLK_PERIOD / 2;

  iImageWidth  <= std_logic_vector(to_unsigned(IMG_W, iImageWidth'length));
  iImageHeight <= std_logic_vector(to_unsigned(IMG_H, iImageHeight'length));

  -- Post-synth netlist: no generic map. Port widths fixed at synth time.
  dut : entity work.openjls_top
    port map
    (
      iClk         => iClk,
      iRst         => iRst,
      iValid       => iValid,
      iPixel       => iPixel,
      oReady       => oReady,
      iImageWidth  => iImageWidth,
      iImageHeight => iImageHeight,
      oData        => oData,
      oValid       => oValid,
      oKeep        => oKeep,
      oLast        => oLast,
      iReady       => iReady
    );

  collect : process (iClk)
  begin
    if rising_edge(iClk) then
      if iRst = '1' then
        collected_count := 0;
        last_count      := 0;
      elsif oValid = '1' and iReady = '1' then
        for i in 0 to BYTES_PER_WORD - 1 loop
          if oKeep(BYTES_PER_WORD - 1 - i) = '1' then
            if collected_count < collected'length then
              collected(collected_count) :=
              oData(OUT_WIDTH - 1 - i * 8 downto OUT_WIDTH - (i + 1) * 8);
            end if;
            collected_count := collected_count + 1;
          end if;
        end loop;
        if oLast = '1' then
          last_count := last_count + 1;
        end if;
      end if;
    end if;
  end process;

  pulse_iReady : process (iClk)
    variable vCount : integer := 0;
  begin
    if rising_edge(iClk) then

      if sPulseIReady = '1' then

        vCount := vCount + 1;
        if vCount = 5 then
          iReady <= '1';
          vCount := 0;
        else
          iReady <= '0';
        end if;

      else
        iReady <= '1';
      end if;

    end if;
  end process;

  stim : process
    variable base_collected : natural := 0;
    variable base_last      : natural := 0;
    procedure do_reset is
    begin
      iRst   <= '1';
      iValid <= '0';
      for i in 0 to 4 loop
        wait until rising_edge(iClk);
      end loop;
      iRst <= '0';
      wait until rising_edge(iClk);
      while oReady /= '1' loop
        wait until rising_edge(iClk);
      end loop;
    end procedure;

    procedure feed_image is
    begin
      for i in PIXELS'range loop
        iPixel <= std_logic_vector(to_unsigned(PIXELS(i), BITNESS));
        iValid <= '1';
        wait until rising_edge(iClk);
      end loop;
      iValid <= '0';
    end procedure;

    procedure feed_image_bp is
    begin
      for i in PIXELS'range loop
        iPixel <= std_logic_vector(to_unsigned(PIXELS(i), BITNESS));
        iValid <= '1';
        wait until oReady = '1' and rising_edge(iClk);
      end loop;
      iValid <= '0';
    end procedure;

    procedure wait_n_images(n : natural) is
    begin
      for i in 0 to 9999 loop
        exit when last_count >= base_last + n;
        wait until rising_edge(iClk);
      end loop;
    end procedure;
  begin

    report "Test 1: single image";
    do_reset;
    base_collected := collected_count;
    base_last      := last_count;
    feed_image;
    wait_n_images(1);

    check(collected_count - base_collected = EXPECTED_BYTES,
    "Test 1 byte count mismatch: got " & integer'image(collected_count - base_collected) &
    " expected " & integer'image(EXPECTED_BYTES));

    for i in 0 to EXPECTED_BYTES - 1 loop
      if base_collected + i < collected_count then
        check(collected(base_collected + i) = EXPECTED(i),
        "Test 1 byte " & integer'image(i) &
        " mismatch: exp=" & hex2(EXPECTED(i)) &
        " got=" & hex2(collected(base_collected + i)));
      end if;
    end loop;
    report "Test 1 done";

    base_collected := collected_count;
    base_last      := last_count;
    wait for CLK_PERIOD * 5;
    wait until rising_edge(iClk);
    report "Test 2: back-to-back images";

    feed_image;
    feed_image;
    wait_n_images(2);

    check(collected_count - base_collected = 2 * EXPECTED_BYTES,
    "Test 2 byte count mismatch: got " & integer'image(collected_count - base_collected) &
    " expected " & integer'image(2 * EXPECTED_BYTES));

    for i in 0 to 2 * EXPECTED_BYTES - 1 loop
      if base_collected + i < collected_count then
        check(collected(base_collected + i) = EXPECTED(i mod EXPECTED_BYTES),
        "Test 2 byte " & integer'image(i) &
        " mismatch: exp=" & hex2(EXPECTED(i mod EXPECTED_BYTES)) &
        " got=" & hex2(collected(base_collected + i)));
      end if;
    end loop;
    report "Test 2 done";

    base_collected := collected_count;
    base_last      := last_count;
    wait for CLK_PERIOD * 5;
    wait until rising_edge(iClk);
    report "Test 3: downstream backpressure";

    sPulseIReady <= '1';

    feed_image_bp;
    feed_image_bp;
    feed_image_bp;
    wait_n_images(3);

    sPulseIReady <= '0';

    check(collected_count - base_collected = 3 * EXPECTED_BYTES,
    "Test 3 byte count mismatch: got " & integer'image(collected_count - base_collected) &
    " expected " & integer'image(3 * EXPECTED_BYTES));

    for i in 0 to 3 * EXPECTED_BYTES - 1 loop
      if base_collected + i < collected_count then
        check(collected(base_collected + i) = EXPECTED(i mod EXPECTED_BYTES),
        "Test 3 byte " & integer'image(i) &
        " mismatch: exp=" & hex2(EXPECTED(i mod EXPECTED_BYTES)) &
        " got=" & hex2(collected(base_collected + i)));
      end if;
    end loop;
    report "Test 3 done";

    if PRINT_BYTES = true then
      for i in 0 to collected_count - 1 loop
        report "got[" & integer'image(i) & "]=" & hex2(collected(i));
      end loop;
    end if;

    if err_count > 0 then
      report "tb_openjls_top_postsynth RESULT: FAIL (" &
        integer'image(err_count) & " errors)" severity failure;
    else
      report "tb_openjls_top_postsynth RESULT: PASS" severity note;
    end if;
    finish;
  end process;

end;
