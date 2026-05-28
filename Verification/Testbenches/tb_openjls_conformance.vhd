----------------------------------------------------------------------------------
  -- Engineer:    Vitor Mendes Camilo
  --
  -- Testbench: tb_openjls_conformance
  --
  -- T.87 conformance test. Loads a single-component PGM image, drives the
  -- encoder, collects the produced JLS stream, writes it to disk under
  -- Verification/Output/, then byte-for-byte compares against a golden
  -- reference .jls file.
  --
  -- Behavioral simulation only: BITNESS=12 here does not match the synthesised
  -- netlist (BITNESS=8). Run from the repo root so the relative paths resolve.
  --
  -- Test image: Verification/jlsimgV100/TEST16.PGM (256x256, 12-bit)
  -- Golden JLS: Verification/jlsimgV100/T16E0.JLS  (NEAR=0)
  -- Output    : Verification/Output/TEST16.JLS
  ----------------------------------------------------------------------------------
  use work.common.all;

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use std.textio.all;
  use std.env.all;

library openlogic_base;
  use openlogic_base.olo_base_pkg_math.log2ceil;

entity tb_openjls_conformance is
  generic (
    REPO_ROOT           : string  := "/home/Vitor/Repos/OpenJLS/";
    POST_SYNTH_FRIENDLY : boolean := true -- if true remove generic map, top level must match the expected generic values
  );
end entity tb_openjls_conformance;

architecture bench of tb_openjls_conformance is

  -------------------------------------------------------------------------------------------------------------
  -- TB level controls
  -------------------------------------------------------------------------------------------------------------
  constant DUMP_VCD              : boolean := false;  -- waveform dump gated; large for 256x256
  constant MAX_DIFF_LOG          : natural := 16;     -- cap on logged byte mismatches before failure

  constant PGM_PATH              : string := REPO_ROOT & "Verification/Reference Images/T87/TEST16.PGM";
  constant JLS_PATH              : string := REPO_ROOT & "Verification/Reference Images/T87/T16E0.JLS";
  constant OUT_PATH              : string := REPO_ROOT & "Verification/Output/T16E0_OPENJLS.JLS";

  -- Test configuration
  constant CLK_PERIOD            : time     := 10 ns;
  constant BITNESS               : natural  := 12;
  constant MAX_IMAGE_WIDTH       : positive := 4096;
  constant MAX_IMAGE_HEIGHT      : positive := 4096;
  constant OUT_WIDTH             : natural  := 64;
  constant BYTES_PER_WORD        : natural  := OUT_WIDTH / 8;

  constant IMG_W                 : natural := 256;
  constant IMG_H                 : natural := 256;
  constant N_PIX                 : natural := IMG_W * IMG_H;

  -- Buffers

  type pixel_array_t is array (natural range <>) of natural;

  type byte_array_t is array (natural range <>) of std_logic_vector(7 downto 0);

  constant COLLECT_CAP           : natural := 262144; -- 256 KB cap, plenty for 256x256 12b

  -- DUT ports
  signal iClk                    : std_logic;
  signal iRst                    : std_logic;
  signal iValid                  : std_logic;
  signal iPixel                  : std_logic_vector(BITNESS - 1 downto 0);
  signal oReady                  : std_logic;
  signal iImageWidth             : std_logic_vector(log2ceil(MAX_IMAGE_WIDTH + 1) - 1 downto 0);
  signal iImageHeight            : std_logic_vector(log2ceil(MAX_IMAGE_HEIGHT + 1) - 1 downto 0);
  signal oData                   : std_logic_vector(OUT_WIDTH - 1 downto 0);
  signal oValid                  : std_logic;
  signal oKeep                   : std_logic_vector(OUT_WIDTH / 8 - 1 downto 0);
  signal oLast                   : std_logic;
  signal iReady                  : std_logic;

  -- Collection
  shared variable collected      : byte_array_t(0 to COLLECT_CAP - 1);
  shared variable collectedCount : natural;
  shared variable lastCount      : natural;

  shared variable errCount       : natural;

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

  function hex2 (
    v : std_logic_vector(7 downto 0)
  ) return string is

    constant HEX : string(1 to 16) := "0123456789ABCDEF";
    variable r   : string(1 to 2);

  begin

    r(1) := HEX(to_integer(unsigned(v(7 downto 4))) + 1);
    r(2) := HEX(to_integer(unsigned(v(3 downto 0))) + 1);
    return r;

  end function hex2;

  -------------------------------------------------------------------------------------------------------------
  -- Binary-byte file I/O (VHDL-2008 file of character)
  -------------------------------------------------------------------------------------------------------------

  type char_file_t is file of character;

  -- Read one byte; sets eof when no more data.

  procedure read_byte (
    file f : char_file_t;
    b      : out std_logic_vector(7 downto 0);
    eof    : out boolean
  ) is

    variable c : character;

  begin

    if endfile(f) then
      eof := true;
      b   := (others => '0');
    else
      read(f, c);
      eof := false;
      b   := std_logic_vector(to_unsigned(character'pos(c), 8));
    end if;

  end procedure read_byte;

  procedure write_byte (
    file f : char_file_t;
    b      : std_logic_vector(7 downto 0)
  ) is

    variable c : character;

  begin

    c := character'val(to_integer(unsigned(b)));
    write(f, c);

  end procedure write_byte;

  -- Read ASCII unsigned decimal integer from PGM header. Skips leading whitespace
  -- and comment lines starting with '#'. Stops on first non-digit (which is
  -- consumed and discarded — the PGM spec says exactly one whitespace separates
  -- the maxval from the binary body, so callers using this for w/h/maxval read
  -- their delimiter implicitly).

  procedure read_pgm_int (
    file f : char_file_t;
    v      : out natural
  ) is

    variable c         : character;
    variable acc       : natural;
    variable started   : boolean;
    variable inComment : boolean;

  begin

    loop

      assert not endfile(f)
        report "PGM: unexpected EOF in header"
        severity failure;
      read(f, c);

      if (inComment) then
        if (c = LF or c = CR) then
          inComment := false;
        end if;
      elsif (not started) then
        if (c = '#') then
          inComment := true;
        elsif (c >= '0' and c <= '9') then
          acc     := character'pos(c) - character'pos('0');
          started := true;
        end if;
      -- else: skip whitespace
      else
        if (c >= '0' and c <= '9') then
          acc := acc * 10 + character'pos(c) - character'pos('0');
        else
          -- delimiter consumed; done
          v := acc;
          return;
        end if;
      end if;

    end loop;

  end procedure read_pgm_int;

begin

  clk_proc : process is
  begin

    iClk <= '0';
    wait for CLK_PERIOD / 2;
    iClk <= '1';
    wait for CLK_PERIOD / 2;

  end process clk_proc;

  -- Image dimensions held stable so the input register latches them during reset.
  iImageWidth  <= std_logic_vector(to_unsigned(IMG_W, iImageWidth'length));
  iImageHeight <= std_logic_vector(to_unsigned(IMG_H, iImageHeight'length));

  dut : if POST_SYNTH_FRIENDLY generate

    dut_post_syn : entity work.openjls_top(rtl)

      port map (
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

  else
    generate

    dut_behav : entity work.openjls_top(rtl)

      generic map (
        BITNESS          => BITNESS,
        MAX_IMAGE_WIDTH  => MAX_IMAGE_WIDTH,
        MAX_IMAGE_HEIGHT => MAX_IMAGE_HEIGHT,
        OUT_WIDTH        => OUT_WIDTH
      )
      port map (
        iClk             => iClk,
        iRst             => iRst,
        iValid           => iValid,
        iPixel           => iPixel,
        oReady           => oReady,
        iImageWidth      => iImageWidth,
        iImageHeight     => iImageHeight,
        oData            => oData,
        oValid           => oValid,
        oKeep            => oKeep,
        oLast            => oLast,
        iReady           => iReady
      );

  end generate dut;

  -- Output collection: extract bytes per word using oKeep (MSB-first).
  collect : process (iClk) is
  begin

    if rising_edge(iClk) then
      if (iRst = '1') then
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

  end process collect;

  -- Stimulus
  stim : process is

    variable pixels : pixel_array_t(0 to N_PIX - 1);
    variable refbuf : byte_array_t(0 to COLLECT_CAP - 1);
    variable refLen : natural;

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

    end procedure do_reset;

    procedure load_pgm (
      path : string
    ) is

      file     f      : char_file_t;
      variable bHi    : std_logic_vector(7 downto 0);
      variable bLo    : std_logic_vector(7 downto 0);
      variable eof    : boolean;
      variable magic0 : std_logic_vector(7 downto 0);
      variable magic1 : std_logic_vector(7 downto 0);
      variable w      : natural;
      variable h      : natural;
      variable mx     : natural;
      variable pix    : natural;

    begin

      file_open(f, path, read_mode);

      -- Magic "P5"
      read_byte(f, magic0, eof);
      read_byte(f, magic1, eof);
      assert magic0 = x"50" and magic1 = x"35"
        report "PGM: magic mismatch (expected P5)"
        severity failure;

      read_pgm_int(f, w);
      read_pgm_int(f, h);
      read_pgm_int(f, mx);
      report "PGM header: w=" & integer'image(w) &
             " h=" & integer'image(h) &
             " maxval=" & integer'image(mx);

      assert w = IMG_W and h = IMG_H
        report "PGM dimensions mismatch"
        severity failure;
      assert mx = (2 ** BITNESS) - 1
        report "PGM maxval does not match BITNESS"
        severity failure;

      -- Body: 2 bytes per pixel, big-endian (maxval > 255)
      for i in 0 to N_PIX - 1 loop

        read_byte(f, bHi, eof);
        assert not eof
          report "PGM: unexpected EOF in body"
          severity failure;
        read_byte(f, bLo, eof);
        assert not eof
          report "PGM: unexpected EOF in body"
          severity failure;
        pix       := to_integer(unsigned(bHi)) * 256 + to_integer(unsigned(bLo));
        assert pix <= mx
          report "PGM: pixel exceeds maxval"
          severity failure;
        pixels(i) := pix;

      end loop;

      file_close(f);

    end procedure load_pgm;

    procedure load_jls (
      path : string
    ) is

      file     f   : char_file_t;
      variable b   : std_logic_vector(7 downto 0);
      variable eof : boolean;
      variable n   : natural;

    begin

      file_open(f, path, read_mode);

      loop

        read_byte(f, b, eof);
        exit when eof;
        assert n < refbuf'length
          report "Reference JLS exceeds buffer"
          severity failure;
        refbuf(n) := b;
        n         := n + 1;

      end loop;

      refLen := n;
      file_close(f);
      report "Reference JLS bytes=" & integer'image(refLen);

    end procedure load_jls;

    procedure save_collected (
      path : string
    ) is

      file f : char_file_t;

    begin

      file_open(f, path, write_mode);

      for i in 0 to collectedCount - 1 loop

        write_byte(f, collected(i));

      end loop;

      file_close(f);
      report "Wrote " & integer'image(collectedCount) & " bytes to " & path;

    end procedure save_collected;

    procedure feed_image is
    begin

      for i in 0 to N_PIX - 1 loop

        iPixel <= std_logic_vector(to_unsigned(pixels(i), BITNESS));
        iValid <= '1';
        wait until oReady = '1' and rising_edge(iClk);

      end loop;

      iValid <= '0';

    end procedure feed_image;

    procedure wait_image is
    begin

      for i in 0 to 1000000 loop

        exit when lastCount >= 1;
        wait until rising_edge(iClk);

      end loop;

    end procedure wait_image;

    variable diffLogged : natural;

  begin

    -- Initial values for signals (no defaults — set explicitly here)
    iRst   <= '1';
    iValid <= '0';
    iPixel <= (others => '0');
    iReady <= '1';

    report "Loading PGM: " & PGM_PATH;
    load_pgm(PGM_PATH);

    report "Loading reference JLS: " & JLS_PATH;
    load_jls(JLS_PATH);

    do_reset;
    report "Feeding " & integer'image(N_PIX) & " pixels";
    feed_image;
    wait_image;

    report "Encoder produced " & integer'image(collectedCount) & " bytes";

    save_collected(OUT_PATH);

    -- Compare full stream byte-for-byte (header is bit-identical for our framer
    -- given matching P/Y/X, so no marker-skip needed)
    check(collectedCount = refLen,
          "Byte count mismatch: got " & integer'image(collectedCount) &
          " expected " & integer'image(refLen));

    for i in 0 to math_min(collectedCount, refLen) - 1 loop

      if (collected(i) /= refbuf(i)) then
        if (diffLogged < MAX_DIFF_LOG) then
          report "Byte " & integer'image(i) &
                 " mismatch: exp=" & hex2(refbuf(i)) &
                 " got=" & hex2(collected(i))
            severity error;
          diffLogged := diffLogged + 1;
        end if;
        errCount := errCount + 1;
      end if;

    end loop;

    if (errCount > 0) then
      report "tb_openjls_conformance RESULT: FAIL (" &
             integer'image(errCount) & " errors)"
        severity failure;
    else
      report "tb_openjls_conformance RESULT: PASS"
        severity note;
    end if;

    finish;

  end process stim;

end architecture bench;
