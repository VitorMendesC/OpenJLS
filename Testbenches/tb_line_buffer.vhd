use work.Common.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.env.all;

entity tb_line_buffer is
end;

architecture bench of tb_line_buffer is
  shared variable err_count : natural := 0;

  procedure check(cond : boolean; msg : string) is
  begin
    if not cond then
      report msg severity error;
      err_count := err_count + 1;
    end if;
  end procedure;

  constant clk_period : time    := 5 ns;
  constant cSettle    : time    := 1 ns; -- combinatorial settle time, << clk_period

  constant IMAGE_W : natural := 10;
  constant IMAGE_H : natural := 10;
  constant BITNESS : natural := CO_BITNESS_STD;

  signal iClk         : std_logic := '1';
  signal iRst         : std_logic := '1';
  signal iImageWidth  : unsigned(3 downto 0) := to_unsigned(IMAGE_W, 4);
  signal iImageHeight : unsigned(3 downto 0) := to_unsigned(IMAGE_H, 4);
  signal iValid       : std_logic := '0';
  signal iPixel       : unsigned(BITNESS - 1 downto 0) := (others => '0');
  signal oA           : unsigned(BITNESS - 1 downto 0);
  signal oB           : unsigned(BITNESS - 1 downto 0);
  signal oC           : unsigned(BITNESS - 1 downto 0);
  signal oD           : unsigned(BITNESS - 1 downto 0);
  signal oValid       : std_logic;
  signal oEOL         : std_logic;
  signal oEOI         : std_logic;

  -- Pixel value for image img, row r, col c: img*W*H + r*W + c
  function pixel_val(img : natural; r : natural; c : natural) return natural is
  begin
    return img * IMAGE_W * IMAGE_H + r * IMAGE_W + c;
  end function;

  -- Expected context neighbors (T.87 A.2.1)
  function exp_a(img : natural; r : natural; c : natural) return natural is
  begin
    if c = 0 then
      if r = 0 then return 0;
      else return pixel_val(img, r - 1, 0); -- first pixel of previous row
      end if;
    else
      return pixel_val(img, r, c - 1);
    end if;
  end function;

  function exp_b(img : natural; r : natural; c : natural) return natural is
  begin
    if r = 0 then return 0;
    else return pixel_val(img, r - 1, c);
    end if;
  end function;

  function exp_c(img : natural; r : natural; c : natural) return natural is
  begin
    if r = 0 then
      return 0;
    elsif c = 0 then
      -- c = first pixel of two rows ago (the Ra from start of previous row)
      if r = 1 then return 0; -- row before row 0 doesn't exist
      else return pixel_val(img, r - 2, 0);
      end if;
    else
      return pixel_val(img, r - 1, c - 1);
    end if;
  end function;

  function exp_d(img : natural; r : natural; c : natural) return natural is
  begin
    if r = 0 then
      return 0;
    elsif c = IMAGE_W - 1 then
      return pixel_val(img, r - 1, c); -- replicate b at last col
    else
      return pixel_val(img, r - 1, c + 1);
    end if;
  end function;

  procedure check_pixel(
    signal sA : in unsigned(BITNESS - 1 downto 0);
    signal sB : in unsigned(BITNESS - 1 downto 0);
    signal sC : in unsigned(BITNESS - 1 downto 0);
    signal sD : in unsigned(BITNESS - 1 downto 0);
    img       : in natural;
    r         : in natural;
    c         : in natural
  ) is
    variable ea, eb, ec, ed : natural;
  begin
    ea := exp_a(img, r, c);
    eb := exp_b(img, r, c);
    ec := exp_c(img, r, c);
    ed := exp_d(img, r, c);

    check(sA = to_unsigned(ea, BITNESS),
      "img=" & natural'image(img) & " (" & natural'image(r) & "," & natural'image(c) & ")" &
      " oA exp=" & natural'image(ea) & " got=" & natural'image(to_integer(sA)));
    check(sB = to_unsigned(eb, BITNESS),
      "img=" & natural'image(img) & " (" & natural'image(r) & "," & natural'image(c) & ")" &
      " oB exp=" & natural'image(eb) & " got=" & natural'image(to_integer(sB)));
    check(sC = to_unsigned(ec, BITNESS),
      "img=" & natural'image(img) & " (" & natural'image(r) & "," & natural'image(c) & ")" &
      " oC exp=" & natural'image(ec) & " got=" & natural'image(to_integer(sC)));
    check(sD = to_unsigned(ed, BITNESS),
      "img=" & natural'image(img) & " (" & natural'image(r) & "," & natural'image(c) & ")" &
      " oD exp=" & natural'image(ed) & " got=" & natural'image(to_integer(sD)));
  end procedure;

  -- Feed one image and check outputs each pixel.
  -- Call this after iRst='0' and just after a rising edge.
  -- Leaves iValid='0' after last pixel's rising edge.
  procedure run_image(
    signal clk   : in  std_logic;
    signal valid : out std_logic;
    signal pixel : out unsigned(BITNESS - 1 downto 0);
    signal sA    : in  unsigned(BITNESS - 1 downto 0);
    signal sB    : in  unsigned(BITNESS - 1 downto 0);
    signal sC    : in  unsigned(BITNESS - 1 downto 0);
    signal sD    : in  unsigned(BITNESS - 1 downto 0);
    signal sEOL  : in  std_logic;
    signal sEOI  : in  std_logic;
    img          : in  natural
  ) is
  begin
    for r in 0 to IMAGE_H - 1 loop
      for c in 0 to IMAGE_W - 1 loop
        -- Drive inputs before the clock edge
        pixel <= to_unsigned(pixel_val(img, r, c), BITNESS);
        valid <= '1';
        -- Let combinatorial outputs settle (registered state already reflects (r,c) position)
        wait for cSettle;
        check_pixel(sA, sB, sC, sD, img, r, c);
        check(sEOL = bool2bit(c = IMAGE_W - 1),
          "img=" & natural'image(img) & " (" & natural'image(r) & "," & natural'image(c) & ") oEOL wrong");
        check(sEOI = bool2bit(r = IMAGE_H - 1 and c = IMAGE_W - 1),
          "img=" & natural'image(img) & " (" & natural'image(r) & "," & natural'image(c) & ") oEOI wrong");
        -- Advance clock: DUT latches pixel, shifts context window
        wait until rising_edge(clk);
      end loop;
    end loop;
    valid <= '0';
  end procedure;

begin

  dut : entity work.line_buffer
    generic map(
      MAX_IMAGE_WIDTH  => IMAGE_W,
      MAX_IMAGE_HEIGHT => IMAGE_H,
      BITNESS          => BITNESS
    )
    port map(
      iClk         => iClk,
      iRst         => iRst,
      iImageWidth  => iImageWidth,
      iImageHeight => iImageHeight,
      iValid       => iValid,
      iPixel       => iPixel,
      oA           => oA,
      oB           => oB,
      oC           => oC,
      oD           => oD,
      oValid       => oValid,
      oEOL         => oEOL,
      oEOI         => oEOI
    );

  iClk <= not iClk after clk_period / 2;

  stim : process
  begin

    -- Reset
    iRst <= '1';
    wait for 3 * clk_period;
    wait until rising_edge(iClk);
    iRst <= '0';
    wait until rising_edge(iClk); -- one idle cycle after reset

    -- =========================================================
    -- Test 1: one image, no reset afterwards
    -- =========================================================
    report "Test 1: single image";
    run_image(iClk, iValid, iPixel, oA, oB, oC, oD, oEOL, oEOI, 0);

    -- A few idle cycles (no reset)
    wait for 3 * clk_period;
    wait until rising_edge(iClk);

    -- =========================================================
    -- Test 2: two images back-to-back (one idle cycle between)
    -- =========================================================
    report "Test 2: two images back-to-back";
    run_image(iClk, iValid, iPixel, oA, oB, oC, oD, oEOL, oEOI, 1);
    -- One idle cycle gap between images
    wait until rising_edge(iClk);
    run_image(iClk, iValid, iPixel, oA, oB, oC, oD, oEOL, oEOI, 2);

    wait for clk_period;

    if err_count > 0 then
      report "tb_line_buffer RESULT: FAIL (" & natural'image(err_count) & " errors)" severity failure;
    else
      report "tb_line_buffer RESULT: PASS" severity note;
    end if;
    finish;

  end process;

end;
