----------------------------------------------------------------------------------
-- Engineer:    Vitor Mendes Camilo
--
-- Testbench: tb_openjls_top
--
-- Drives the T.87 Annex H.3 example (4x4, 8-bit, NEAR=0) through the
-- end-to-end encoder and compares the output stream against the expected
-- 57-byte sequence:
--   * 25-byte JPEG-LS header (SOI + SOF55 + SOS)
--   * 30-byte compressed payload (T.87 H.3 Table H.x)
--   * 2-byte EOI footer (FF D9)
----------------------------------------------------------------------------------
use work.Common.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.env.all;

library openlogic_base;
use openlogic_base.olo_base_pkg_math.log2ceil;

entity tb_openjls_top is
end;

architecture bench of tb_openjls_top is

  -- Test configuration
  constant CLK_PERIOD       : time     := 10 ns;
  constant BITNESS          : natural  := 8;
  constant MAX_IMAGE_WIDTH  : positive := 16;
  constant MAX_IMAGE_HEIGHT : positive := 16;
  constant OUT_WIDTH        : natural  := CO_OUT_WIDTH_STD;
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
  -- Header (25 B): SOI FF D8, SOF55 FF F7 + Lf + P + Y + X + Nf + C1/H1V1/Tq1,
  -- SOS FF DA + Ls + Ns + Cs1/Tm1 + NEAR + ILV/AlAh.
  x"FF", x"D8",
  x"FF", x"F7", x"00", x"0B", x"08", x"00", x"04", x"00", x"04",
  x"01", x"01", x"11", x"00",
  x"FF", x"DA", x"00", x"08", x"01", x"01", x"00", x"00", x"00", x"00",
  -- Payload (30 B): T.87 Annex H.3 compressed body, last byte 0x60 is
  -- 3 meaningful bits `011` + 5 zero-pad bits from bit-packer flush.
  x"C0", x"00", x"00", x"6C",
  x"80", x"20", x"8E", x"01",
  x"C0", x"00", x"00", x"57",
  x"40", x"00", x"00", x"6E",
  x"E6", x"00", x"00", x"01",
  x"BC", x"18", x"00", x"00",
  x"05", x"D8", x"00", x"00",
  x"91", x"60",
  -- Footer (2 B)
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

  signal sDone : std_logic := '0';

  -- Collection
  shared variable collected       : byte_array_t(0 to 127) := (others => (others => '0'));
  shared variable collected_count : natural                := 0;

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

  -- Clock
  iClk <= not iClk after CLK_PERIOD / 2;

  -- Image dimensions: held stable so the input register latches them during reset.
  iImageWidth  <= std_logic_vector(to_unsigned(IMG_W, iImageWidth'length));
  iImageHeight <= std_logic_vector(to_unsigned(IMG_H, iImageHeight'length));

  dut : entity work.openjls_top
    generic map(
      BITNESS          => BITNESS,
      MAX_IMAGE_WIDTH  => MAX_IMAGE_WIDTH,
      MAX_IMAGE_HEIGHT => MAX_IMAGE_HEIGHT,
      OUT_WIDTH        => OUT_WIDTH
    )
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

  -- Output collection: extract bytes per word using oKeep (MSB-first).
  collect : process (iClk)
  begin
    if rising_edge(iClk) then
      if iRst = '1' then
        collected_count := 0;
        sDone <= '0';
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
          sDone <= '1';
        end if;
      end if;
    end if;
  end process;

  -- Stimulus
  stim : process
  begin
    -- Hold reset for several clocks; iImageWidth/Height already stable.
    iRst   <= '1';
    iValid <= '0';
    iReady <= '1';
    for i in 0 to 4 loop
      wait until rising_edge(iClk);
    end loop;

    iRst <= '0';
    wait until rising_edge(iClk);

    -- Wait for the encoder to come ready.
    while oReady /= '1' loop
      wait until rising_edge(iClk);
    end loop;

    -- Feed all 16 pixels, one per clock. Handshake: top latches on
    -- (iValid and sReady). oReady stays high throughout.
    for i in PIXELS'range loop
      iPixel <= std_logic_vector(to_unsigned(PIXELS(i), BITNESS));
      iValid <= '1';
      wait until rising_edge(iClk);
    end loop;
    iValid <= '0';

    -- Drain: wait for the framer to emit the full stream (header + payload +
    -- footer), signalled by oLast. Generous timeout for the flush FSM.
    for i in 0 to 999 loop
      exit when sDone = '1';
      wait until rising_edge(iClk);
    end loop;

    -- Comparison
    check(collected_count = EXPECTED_BYTES,
    "Byte count mismatch: got " & integer'image(collected_count) &
    " expected " & integer'image(EXPECTED_BYTES));

    for i in 0 to EXPECTED_BYTES - 1 loop
      if i < collected_count then
        check(collected(i) = EXPECTED(i),
        "Byte " & integer'image(i) &
        " mismatch: exp=" & hex2(EXPECTED(i)) &
        " got=" & hex2(collected(i)));
      end if;
    end loop;

    if err_count > 0 then
      report "tb_openjls_top RESULT: FAIL (" &
        integer'image(err_count) & " errors)" severity failure;
    else
      report "tb_openjls_top RESULT: PASS" severity note;
    end if;
    finish;
  end process;

end;
