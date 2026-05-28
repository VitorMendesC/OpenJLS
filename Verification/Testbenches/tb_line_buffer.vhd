use work.common.all;

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library openlogic_base;
  use openlogic_base.olo_base_pkg_math.log2ceil;
  use std.env.all;

entity tb_line_buffer is
end entity tb_line_buffer;

architecture bench of tb_line_buffer is

  shared variable errCount : natural;

  procedure check (
    cond : boolean;
    msg  : string
  ) is
  begin

    if (not cond) then
      report msg
        severity error;
      errCount := errCount + 1;
    end if;

  end procedure check;

  constant CLK_PERIOD      : time    := 5 ns;
  constant CSETTLE         : time    := 1 ns;
  constant BITNESS         : natural := CO_BITNESS_STD;

  -- DUT is sized for the largest image
  constant MAX_W           : natural := 10;
  constant MAX_H           : natural := 10;

  signal iClk              : std_logic;
  signal iRst              : std_logic;
  signal iImageWidth       : unsigned(log2ceil(MAX_W + 1) - 1 downto 0);
  signal iImageHeight      : unsigned(log2ceil(MAX_H + 1) - 1 downto 0);
  signal iValid            : std_logic;
  signal iPixel            : unsigned(BITNESS - 1 downto 0);
  signal oA                : unsigned(BITNESS - 1 downto 0);
  signal oB                : unsigned(BITNESS - 1 downto 0);
  signal oC                : unsigned(BITNESS - 1 downto 0);
  signal oD                : unsigned(BITNESS - 1 downto 0);
  signal oValid            : std_logic;
  signal oEol              : std_logic;
  signal oEoi              : std_logic;

  -- Reference functions, parameterized by image dimensions

  function pixel_val (
    img,
    r,
    c,
    w,
    h : natural
  ) return natural is
  begin

    return img * w * h + r * w + c;

  end function pixel_val;

  function expa (
    img,
    r,
    c,
    w,
    h : natural
  ) return natural is
  begin

    if (c = 0) then
      if (r = 0) then
        return 0;
      else
        return pixel_val(img, r - 1, 0, w, h);
      end if;
    else
      return pixel_val(img, r, c - 1, w, h);
    end if;

  end function expa;

  function expb (
    img,
    r,
    c,
    w,
    h : natural
  ) return natural is
  begin

    if (r = 0) then
      return 0;
    else
      return pixel_val(img, r - 1, c, w, h);
    end if;

  end function expb;

  function expc (
    img,
    r,
    c,
    w,
    h : natural
  ) return natural is
  begin

    if (r = 0) then
      return 0;
    elsif (c = 0) then
      if (r = 1) then
        return 0;
      else
        return pixel_val(img, r - 2, 0, w, h);
      end if;
    else
      return pixel_val(img, r - 1, c - 1, w, h);
    end if;

  end function expc;

  function exp_d (
    img,
    r,
    c,
    w,
    h : natural
  ) return natural is
  begin

    if (r = 0) then
      return 0;
    elsif (c = w - 1) then
      return pixel_val(img, r - 1, c, w, h); -- replicate b at last col
    else
      return pixel_val(img, r - 1, c + 1, w, h);
    end if;

  end function exp_d;

  procedure check_pixel (
    signal sa : in unsigned(BITNESS - 1 downto 0);
    signal sb : in unsigned(BITNESS - 1 downto 0);
    signal sc : in unsigned(BITNESS - 1 downto 0);
    signal sd : in unsigned(BITNESS - 1 downto 0);
    img,
    r,
    c,
    w,
    h         : in natural
  ) is

    variable ea : natural;
    variable eb : natural;
    variable ec : natural;
    variable ed : natural;

  begin

    ea := expA(img, r, c, w, h);
    eb := expB(img, r, c, w, h);
    ec := expC(img, r, c, w, h);
    ed := exp_d(img, r, c, w, h);

    check(sa = to_unsigned(ea, BITNESS),
          "img=" & natural'image(img) & " (" & natural'image(r) & "," & natural'image(c) & ")" &
          " oA exp=" & natural'image(ea) & " got=" & natural'image(to_integer(sa)));
    check(sb = to_unsigned(eb, BITNESS),
          "img=" & natural'image(img) & " (" & natural'image(r) & "," & natural'image(c) & ")" &
          " oB exp=" & natural'image(eb) & " got=" & natural'image(to_integer(sb)));
    check(sc = to_unsigned(ec, BITNESS),
          "img=" & natural'image(img) & " (" & natural'image(r) & "," & natural'image(c) & ")" &
          " oC exp=" & natural'image(ec) & " got=" & natural'image(to_integer(sc)));
    check(sd = to_unsigned(ed, BITNESS),
          "img=" & natural'image(img) & " (" & natural'image(r) & "," & natural'image(c) & ")" &
          " oD exp=" & natural'image(ed) & " got=" & natural'image(to_integer(sd)));

  end procedure check_pixel;

  procedure run_image (
    signal clk   : in  std_logic;
    signal valid : out std_logic;
    signal pixel : out unsigned(BITNESS - 1 downto 0);
    signal sa    : in  unsigned(BITNESS - 1 downto 0);
    signal sb    : in  unsigned(BITNESS - 1 downto 0);
    signal sc    : in  unsigned(BITNESS - 1 downto 0);
    signal sd    : in  unsigned(BITNESS - 1 downto 0);
    signal seol  : in  std_logic;
    signal seoi  : in  std_logic;
    img,
    w,
    h            : in  natural
  ) is
  begin

    for r in 0 to h - 1 loop

      for c in 0 to w - 1 loop

        pixel <= to_unsigned(pixel_val(img, r, c, w, h), BITNESS);
        valid <= '1';
        wait for cSettle;
        check_pixel(sa, sb, sc, sd, img, r, c, w, h);
        check(seol = bool2bit(c = w - 1),
              "img=" & natural'image(img) & " (" & natural'image(r) & "," & natural'image(c) & ") oEol wrong");
        check(seoi = bool2bit(r = h - 1 and c = w - 1),
              "img=" & natural'image(img) & " (" & natural'image(r) & "," & natural'image(c) & ") oEoi wrong");
        wait until rising_edge(clk);

      end loop;

    end loop;

    valid <= '0';

  end procedure run_image;

begin

  clk_proc : process is
  begin

    iClk <= '1';
    wait for CLK_PERIOD / 2;
    iClk <= '0';
    wait for CLK_PERIOD / 2;

  end process clk_proc;

  dut : entity work.line_buffer(behavioral)

    generic map (
      MAX_IMAGE_WIDTH  => MAX_W,
      MAX_IMAGE_HEIGHT => MAX_H,
      BITNESS          => BITNESS
    )
    port map (
      iClk             => iClk,
      iRst             => iRst,
      iImageWidth      => iImageWidth,
      iImageHeight     => iImageHeight,
      iValid           => iValid,
      iPixel           => iPixel,
      oA               => oA,
      oB               => oB,
      oC               => oC,
      oD               => oD,
      oValid           => oValid,
      oEol             => oEol,
      oEoi             => oEoi
    );

  stim : process is

    constant W5  : natural := 5;
    constant H5  : natural := 5;
    constant W10 : natural := 10;
    constant H10 : natural := 10;

  begin

    -- Initial values (no defaults — set explicitly here)
    iRst   <= '1';
    iValid <= '0';
    iPixel <= (others => '0');

    iRst <= '1';
    wait for 3 * CLK_PERIOD;
    wait until rising_edge(iClk);
    iRst <= '0';
    wait until rising_edge(iClk);

    -- =========================================================
    -- 5x5 Test 1: one image, no reset afterwards
    -- =========================================================
    report "5x5 Test 1: single image";
    iImageWidth  <= to_unsigned(W5, iImageWidth'length);
    iImageHeight <= to_unsigned(H5, iImageHeight'length);

    run_image(iClk, iValid, iPixel, oA, oB, oC, oD, oEol, oEoi, 0, W5, H5);

    wait for 3 * CLK_PERIOD;
    wait until rising_edge(iClk);

    -- =========================================================
    -- 5x5 Test 2: two images back-to-back, no bubble
    -- =========================================================
    report "5x5 Test 2: two images back-to-back";
    run_image(iClk, iValid, iPixel, oA, oB, oC, oD, oEol, oEoi, 0, W5, H5);
    run_image(iClk, iValid, iPixel, oA, oB, oC, oD, oEol, oEoi, 0, W5, H5);

    -- Wait between image size changes (no reset, DUT returns to PRELOAD after EOI)
    wait for 10 * CLK_PERIOD;
    wait until rising_edge(iClk);

    -- =========================================================
    -- 10x10 Test 1: one image, no reset afterwards
    -- =========================================================
    report "10x10 Test 1: single image";
    iImageWidth  <= to_unsigned(W10, iImageWidth'length);
    iImageHeight <= to_unsigned(H10, iImageHeight'length);

    run_image(iClk, iValid, iPixel, oA, oB, oC, oD, oEol, oEoi, 0, W10, H10);

    wait for 3 * CLK_PERIOD;
    wait until rising_edge(iClk);

    -- =========================================================
    -- 10x10 Test 2: two images back-to-back, no bubble
    -- =========================================================
    report "10x10 Test 2: two images back-to-back";
    run_image(iClk, iValid, iPixel, oA, oB, oC, oD, oEol, oEoi, 1, W10, H10);
    run_image(iClk, iValid, iPixel, oA, oB, oC, oD, oEol, oEoi, 2, W10, H10);

    wait for CLK_PERIOD;

    if (errCount > 0) then
      report "tb_line_buffer RESULT: FAIL (" & natural'image(errCount) & " errors)"
        severity failure;
    else
      report "tb_line_buffer RESULT: PASS"
        severity note;
    end if;

    finish;

  end process stim;

end architecture bench;
