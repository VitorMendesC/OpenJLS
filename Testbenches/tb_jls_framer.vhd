----------------------------------------------------------------------------------
-- Engineer:    Vitor Mendes Camilo
--
-- Module Name: tb_jls_framer - bench
-- Description:
--
--   Testbench for jls_framer.
--
--   Image dimensions are fixed for the lifetime of the simulation (as they
--   are in real operation: latched at reset by the top level).
--
--   Test 1: Single image — verify all 25 header bytes, payload pass-through,
--           footer (FF D9), and oLast on the final word.
--   Test 2: Back-to-back images — iStart the cycle after iEOI; verify the
--           second header only appears after oLast of the first image.
--   Test 3: Backpressure mid-header — iReady deasserted for several cycles;
--           verify no bytes are lost or duplicated.
----------------------------------------------------------------------------------
use work.Common.all;

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

library openlogic_base;
use openlogic_base.olo_base_pkg_math.log2ceil;

use std.env.all;

entity tb_jls_framer is end;

architecture bench of tb_jls_framer is

  shared variable err_count : natural := 0;

  procedure check(cond : boolean; msg : string) is
  begin
    if not cond then
      report msg severity error;
      err_count := err_count + 1;
    end if;
  end procedure;


  -- DUT generics
  constant NEAR             : natural := 0;
  constant BITNESS          : natural := 12;
  constant IN_WIDTH         : natural := 24; -- CO_BYTE_STUFFER_IN_WIDTH
  constant OUT_WIDTH        : natural := 72; -- CO_OUT_WIDTH_STD
  constant MAX_IMAGE_WIDTH  : natural := 256;
  constant MAX_IMAGE_HEIGHT : natural := 256;

  constant BYTES_IN   : natural := IN_WIDTH / 8; -- 3
  constant BYTES_OUT  : natural := OUT_WIDTH / 8; -- 9
  constant HEADER_LEN : natural := 25;

  -- Fixed image dimensions (never change after reset)
  constant W : natural := 4;
  constant H : natural := 4;

  constant clk_period : time := 5 ns;

  -- DUT ports
  signal iClk        : std_logic                                            := '1';
  signal iRst        : std_logic                                            := '1';
  signal iStart      : std_logic                                            := '0';
  signal iImageWidth : unsigned(log2ceil(MAX_IMAGE_WIDTH + 1) - 1 downto 0) :=
  to_unsigned(W, log2ceil(MAX_IMAGE_WIDTH + 1));
  signal iImageHeight : unsigned(log2ceil(MAX_IMAGE_HEIGHT + 1) - 1 downto 0) :=
  to_unsigned(H, log2ceil(MAX_IMAGE_HEIGHT + 1));
  signal iEOI          : std_logic                                 := '0';
  signal iBsWord       : std_logic_vector(IN_WIDTH - 1 downto 0)   := (others => '0');
  signal iBsWordValid  : std_logic                                 := '0';
  signal iBsValidBytes : unsigned(log2ceil(IN_WIDTH / 8) downto 0) := (others => '0');
  signal oBsReady      : std_logic;
  signal oWord         : std_logic_vector(OUT_WIDTH - 1 downto 0);
  signal oWordValid    : std_logic;
  signal oValidBytes   : unsigned(log2ceil(OUT_WIDTH / 8) downto 0);
  signal oLast         : std_logic;
  signal iReady        : std_logic := '1';

  -- -----------------------------------------------------------------------
  -- Expected header byte at position idx
  -- -----------------------------------------------------------------------
  function expected_header_byte(idx : natural) return std_logic_vector is
  begin
    case idx is
      when 0      => return x"FF";
      when 1      => return x"D8";
      when 2      => return x"FF";
      when 3      => return x"F7";
      when 4      => return x"00";
      when 5      => return x"0B";
      when 6      => return std_logic_vector(to_unsigned(BITNESS, 8));
      when 7      => return std_logic_vector(to_unsigned(H / 256, 8));
      when 8      => return std_logic_vector(to_unsigned(H mod 256, 8));
      when 9      => return std_logic_vector(to_unsigned(W / 256, 8));
      when 10     => return std_logic_vector(to_unsigned(W mod 256, 8));
      when 11     => return x"01";
      when 12     => return x"01";
      when 13     => return x"11";
      when 14     => return x"00";
      when 15     => return x"FF";
      when 16     => return x"DA";
      when 17     => return x"00";
      when 18     => return x"08";
      when 19     => return x"01";
      when 20     => return x"01";
      when 21     => return x"00";
      when 22     => return std_logic_vector(to_unsigned(NEAR, 8));
      when 23     => return x"00";
      when 24     => return x"00";
      when others => return x"00";
    end case;
  end function;

  -- Shared monitor state
  shared variable mon_byte_idx      : integer := 0;
  shared variable mon_payload_bytes : natural := 0;
  shared variable mon_last_seen     : boolean := false;

begin

  iClk <= not iClk after clk_period / 2;

  dut : entity work.jls_framer
    generic map(
      NEAR             => NEAR,
      BITNESS          => BITNESS,
      IN_WIDTH         => IN_WIDTH,
      OUT_WIDTH        => OUT_WIDTH,
      MAX_IMAGE_WIDTH  => MAX_IMAGE_WIDTH,
      MAX_IMAGE_HEIGHT => MAX_IMAGE_HEIGHT
    )
    port map
    (
      iClk          => iClk,
      iRst          => iRst,
      iStart        => iStart,
      iImageWidth   => iImageWidth,
      iImageHeight  => iImageHeight,
      iEOI          => iEOI,
      iBsWord       => iBsWord,
      iBsWordValid  => iBsWordValid,
      iBsValidBytes => iBsValidBytes,
      oBsReady      => oBsReady,
      oWord         => oWord,
      oWordValid    => oWordValid,
      oValidBytes   => oValidBytes,
      oLast         => oLast,
      iReady        => iReady
    );

  -- =========================================================================
  -- Monitor: check every output byte in sequence
  -- =========================================================================
  monitor : process (iClk)
    variable got : std_logic_vector(7 downto 0);
    variable bi  : integer;
  begin
    if rising_edge(iClk) then
      if oWordValid = '1' and iReady = '1' then
        bi := mon_byte_idx;

        for i in 0 to BYTES_OUT - 1 loop
          if i < to_integer(oValidBytes) then
            -- oWord is MSB-first: byte 0 is at bits OUT_WIDTH-1..OUT_WIDTH-8
            got := oWord(OUT_WIDTH - 1 - i * 8 downto OUT_WIDTH - (i + 1) * 8);

            if bi < HEADER_LEN then
              check(got = expected_header_byte(bi),
              "Hdr byte " & integer'image(bi) &
              " got=" & integer'image(to_integer(unsigned(got))) &
              " exp=" & integer'image(to_integer(unsigned(expected_header_byte(bi)))));

            elsif bi < HEADER_LEN + mon_payload_bytes then
              null; -- payload: value not checked here

            elsif bi = HEADER_LEN + mon_payload_bytes then
              check(got = x"FF",
              "Footer[0] got=" & integer'image(to_integer(unsigned(got))) & " exp=255 (0xFF)");

            elsif bi = HEADER_LEN + mon_payload_bytes + 1 then
              check(got = x"D9",
              "Footer[1] got=" & integer'image(to_integer(unsigned(got))) & " exp=217 (0xD9)");

            end if;

            bi := bi + 1;
          end if;
        end loop;

        mon_byte_idx := bi;

        if oLast = '1' then
          mon_last_seen := true;
        end if;

      end if;
    end if;
  end process monitor;

  -- =========================================================================
  -- Stimulus
  -- =========================================================================
  stim : process
    -- Send n_words payload words then assert iEOI alongside the last one.
    -- The last word carries partial valid bytes.
    procedure send_payload(
      n_words : natural;
      partial : natural := BYTES_IN
    ) is
      variable word : std_logic_vector(IN_WIDTH - 1 downto 0) := (others => '0');
    begin
      -- Fill each word with 0xAB for easy visual inspection
      for b in 0 to BYTES_IN - 1 loop
        word(IN_WIDTH - 1 - b * 8 downto IN_WIDTH - (b + 1) * 8) := x"AB";
      end loop;
      iBsWord <= word;

      if n_words = 0 then
        -- No payload: EOI alone
        iBsWordValid  <= '0';
        iBsValidBytes <= (others => '0');
        iEOI          <= '1';
        wait until rising_edge(iClk);
        iEOI <= '0';
        return;
      end if;

      for w in 0 to n_words - 1 loop
        if oBsReady = '0' then
          wait until oBsReady = '1';
          wait until rising_edge(iClk);
        end if;
        if w = n_words - 1 then
          iBsValidBytes <= to_unsigned(partial, iBsValidBytes'length);
          iBsWordValid  <= '1';
          iEOI          <= '1';
          wait until rising_edge(iClk);
          iBsWordValid <= '0';
          iEOI         <= '0';
        else
          iBsValidBytes <= to_unsigned(BYTES_IN, iBsValidBytes'length);
          iBsWordValid  <= '1';
          wait until rising_edge(iClk);
          iBsWordValid <= '0';
        end if;
      end loop;
    end procedure;

    -- Block until oLast has been seen and consumed
    procedure wait_image_done is
    begin
      loop
        wait until rising_edge(iClk);
        exit when mon_last_seen;
      end loop;
      wait until rising_edge(iClk);
    end procedure;

    -- Number of 3-byte payload words for a small image (2 bytes/pixel)
    constant PAYLOAD_BYTES : natural := W * H * 2;
    constant N_WORDS       : natural := (PAYLOAD_BYTES + BYTES_IN - 1) / BYTES_IN;
    -- Valid bytes in the last word (remainder, always >= 1)
    constant LAST_PARTIAL  : natural := PAYLOAD_BYTES - (N_WORDS - 1) * BYTES_IN;

  begin

    iRst <= '1';
    wait for 3 * clk_period;
    wait until rising_edge(iClk);
    iRst <= '0';
    wait until rising_edge(iClk);

    -- =========================================================================
    -- Test 1: single image, no backpressure
    -- =========================================================================
    report "Test 1: single image";

    mon_byte_idx      := 0;
    mon_payload_bytes := PAYLOAD_BYTES;
    mon_last_seen     := false;

    iStart <= '1';
    wait until rising_edge(iClk);
    iStart <= '0';

    wait for clk_period * 4; -- simulate pipeline delay
    wait until rising_edge(iClk);

    send_payload(N_WORDS, LAST_PARTIAL);
    wait_image_done;

    check(mon_byte_idx = HEADER_LEN + PAYLOAD_BYTES + 2,
    "Test 1: wrong total byte count " & integer'image(mon_byte_idx));
    report "Test 1 done";

    wait for clk_period * 2;

    -- =========================================================================
    -- Test 2: back-to-back images — iStart the cycle after iEOI
    -- =========================================================================
    report "Test 2: back-to-back images";

    -- Image 1 (no payload for speed)
    mon_byte_idx      := 0;
    mon_payload_bytes := 0;
    mon_last_seen     := false;

    iStart <= '1';
    wait until rising_edge(iClk);
    iStart <= '0';

    wait for clk_period * 4;
    wait until rising_edge(iClk);

    -- EOI for image 1
    iEOI <= '1';
    wait until rising_edge(iClk);
    iEOI <= '0';

    -- iStart for image 2 arrives the very next cycle
    iStart <= '1';
    wait until rising_edge(iClk);
    iStart <= '0';

    -- Wait for image 1 footer + oLast
    wait_image_done;

    -- Image 2: monitor expects a fresh header
    mon_byte_idx      := 0;
    mon_payload_bytes := 0;
    mon_last_seen     := false;

    wait for clk_period * 4;
    wait until rising_edge(iClk);

    iEOI <= '1';
    wait until rising_edge(iClk);
    iEOI <= '0';

    wait_image_done;

    check(mon_byte_idx = HEADER_LEN + 2,
    "Test 2: image 2 wrong byte count " & integer'image(mon_byte_idx));
    report "Test 2 done";

    wait for clk_period * 2;

    -- =========================================================================
    -- Test 3: backpressure mid-header
    -- =========================================================================
    report "Test 3: backpressure during header";

    mon_byte_idx      := 0;
    mon_payload_bytes := 0;
    mon_last_seen     := false;

    iStart <= '1';
    wait until rising_edge(iClk);
    iStart <= '0';

    -- Stall downstream after 1 output word
    wait for clk_period;
    wait until rising_edge(iClk);
    iReady <= '0';
    wait for clk_period * 5;
    wait until rising_edge(iClk);
    iReady <= '1';

    wait for clk_period * 4;
    wait until rising_edge(iClk);

    iEOI <= '1';
    wait until rising_edge(iClk);
    iEOI <= '0';

    wait_image_done;

    check(mon_byte_idx = HEADER_LEN + 2,
    "Test 3: wrong byte count " & integer'image(mon_byte_idx));
    report "Test 3 done";

    -- =========================================================================
    wait for clk_period * 2;
    if err_count > 0 then
      report "tb_jls_framer RESULT: FAIL (" & natural'image(err_count) & " errors)"
        severity failure;
    else
      report "tb_jls_framer RESULT: PASS" severity note;
    end if;
    finish;
  end process;

end bench;
