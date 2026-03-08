use work.Common.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library openlogic_base;
use openlogic_base.olo_base_pkg_math.log2ceil;

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
  constant cSettle    : time    := 1 ns;
  constant BITNESS    : natural := CO_BITNESS_STD;

  -- DUT is sized for the largest image
  constant MAX_W : natural := 10;
  constant MAX_H : natural := 10;

  signal iClk        : std_logic := '1';
  signal iRst        : std_logic := '1';
  signal iImageWidth : unsigned(log2ceil(MAX_W + 1) - 1 downto 0) := (others => '0');
  signal iImageHeight: unsigned(log2ceil(MAX_H + 1) - 1 downto 0) := (others => '0');
  signal iValid      : std_logic := '0';
  signal iPixel      : unsigned(BITNESS - 1 downto 0) := (others => '0');
  signal oA, oB, oC, oD : unsigned(BITNESS - 1 downto 0);
  signal oValid, oEOL, oEOI : std_logic;

  -- Reference functions, parameterized by image dimensions
  function pixel_val(img, r, c, W, H : natural) return natural is
  begin
    return img * W * H + r * W + c;
  end function;

  function exp_a(img, r, c, W, H : natural) return natural is
  begin
    if c = 0 then
      if r = 0 then return 0;
      else return pixel_val(img, r - 1, 0, W, H);
      end if;
    else
      return pixel_val(img, r, c - 1, W, H);
    end if;
  end function;

  function exp_b(img, r, c, W, H : natural) return natural is
  begin
    if r = 0 then return 0;
    else return pixel_val(img, r - 1, c, W, H);
    end if;
  end function;

  function exp_c(img, r, c, W, H : natural) return natural is
  begin
    if r = 0 then
      return 0;
    elsif c = 0 then
      if r = 1 then return 0;
      else return pixel_val(img, r - 2, 0, W, H);
      end if;
    else
      return pixel_val(img, r - 1, c - 1, W, H);
    end if;
  end function;

  function exp_d(img, r, c, W, H : natural) return natural is
  begin
    if r = 0 then
      return 0;
    elsif c = W - 1 then
      return pixel_val(img, r - 1, c, W, H); -- replicate b at last col
    else
      return pixel_val(img, r - 1, c + 1, W, H);
    end if;
  end function;

  procedure check_pixel(
    signal sA        : in unsigned(BITNESS - 1 downto 0);
    signal sB        : in unsigned(BITNESS - 1 downto 0);
    signal sC        : in unsigned(BITNESS - 1 downto 0);
    signal sD        : in unsigned(BITNESS - 1 downto 0);
    img, r, c, W, H : in natural
  ) is
    variable ea, eb, ec, ed : natural;
  begin
    ea := exp_a(img, r, c, W, H);
    eb := exp_b(img, r, c, W, H);
    ec := exp_c(img, r, c, W, H);
    ed := exp_d(img, r, c, W, H);

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

  procedure run_image(
    signal clk        : in  std_logic;
    signal valid      : out std_logic;
    signal pixel      : out unsigned(BITNESS - 1 downto 0);
    signal sA         : in  unsigned(BITNESS - 1 downto 0);
    signal sB         : in  unsigned(BITNESS - 1 downto 0);
    signal sC         : in  unsigned(BITNESS - 1 downto 0);
    signal sD         : in  unsigned(BITNESS - 1 downto 0);
    signal sEOL       : in  std_logic;
    signal sEOI       : in  std_logic;
    img, W, H         : in  natural
  ) is
  begin
    for r in 0 to H - 1 loop
      for c in 0 to W - 1 loop
        pixel <= to_unsigned(pixel_val(img, r, c, W, H), BITNESS);
        valid <= '1';
        wait for cSettle;
        check_pixel(sA, sB, sC, sD, img, r, c, W, H);
        check(sEOL = bool2bit(c = W - 1),
          "img=" & natural'image(img) & " (" & natural'image(r) & "," & natural'image(c) & ") oEOL wrong");
        check(sEOI = bool2bit(r = H - 1 and c = W - 1),
          "img=" & natural'image(img) & " (" & natural'image(r) & "," & natural'image(c) & ") oEOI wrong");
        wait until rising_edge(clk);
      end loop;
    end loop;
    valid <= '0';
  end procedure;

begin

  iClk <= not iClk after clk_period / 2;

  dut : entity work.line_buffer
    generic map(
      MAX_IMAGE_WIDTH  => MAX_W,
      MAX_IMAGE_HEIGHT => MAX_H,
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

  stim : process
    constant W5  : natural := 5;
    constant H5  : natural := 5;
    constant W10 : natural := 10;
    constant H10 : natural := 10;
  begin

    iRst <= '1';
    wait for 3 * clk_period;
    wait until rising_edge(iClk);
    iRst <= '0';
    wait until rising_edge(iClk);

    -- =========================================================
    -- 5x5 Test 1: one image, no reset afterwards
    -- =========================================================
    report "5x5 Test 1: single image";
    iImageWidth  <= to_unsigned(W5, iImageWidth'length);
    iImageHeight <= to_unsigned(H5, iImageHeight'length);

    run_image(iClk, iValid, iPixel, oA, oB, oC, oD, oEOL, oEOI, 0, W5, H5);

    wait for 3 * clk_period;
    wait until rising_edge(iClk);

    -- =========================================================
    -- 5x5 Test 2: two images back-to-back, no bubble
    -- =========================================================
    report "5x5 Test 2: two images back-to-back";
    run_image(iClk, iValid, iPixel, oA, oB, oC, oD, oEOL, oEOI, 0, W5, H5);
    run_image(iClk, iValid, iPixel, oA, oB, oC, oD, oEOL, oEOI, 0, W5, H5);

    -- Wait between image size changes (no reset, DUT returns to PRELOAD after EOI)
    wait for 10 * clk_period;
    wait until rising_edge(iClk);

    -- =========================================================
    -- 10x10 Test 1: one image, no reset afterwards
    -- =========================================================
    report "10x10 Test 1: single image";
    iImageWidth  <= to_unsigned(W10, iImageWidth'length);
    iImageHeight <= to_unsigned(H10, iImageHeight'length);

    run_image(iClk, iValid, iPixel, oA, oB, oC, oD, oEOL, oEOI, 0, W10, H10);

    wait for 3 * clk_period;
    wait until rising_edge(iClk);

    -- =========================================================
    -- 10x10 Test 2: two images back-to-back, no bubble
    -- =========================================================
    report "10x10 Test 2: two images back-to-back";
    run_image(iClk, iValid, iPixel, oA, oB, oC, oD, oEOL, oEOI, 1, W10, H10);
    run_image(iClk, iValid, iPixel, oA, oB, oC, oD, oEOL, oEOI, 2, W10, H10);

    wait for clk_period;

    if err_count > 0 then
      report "tb_line_buffer RESULT: FAIL (" & natural'image(err_count) & " errors)" severity failure;
    else
      report "tb_line_buffer RESULT: PASS" severity note;
    end if;
    finish;

  end process;

end;
