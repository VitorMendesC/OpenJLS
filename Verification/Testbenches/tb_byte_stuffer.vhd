library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library openlogic_base;
  use openlogic_base.olo_base_pkg_math.log2ceil;
  use work.common.all;
  use std.env.all;

entity tb_byte_stuffer is
end entity tb_byte_stuffer;

architecture bench of tb_byte_stuffer is

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

  function hex (
    v : std_logic_vector(7 downto 0)
  ) return string is

    constant HEX : string(1 to 16) := "0123456789ABCDEF";
    variable r   : string(1 to 2);

  begin

    r(1) := HEX(to_integer(unsigned(v(7 downto 4))) + 1);
    r(2) := HEX(to_integer(unsigned(v(3 downto 0))) + 1);
    return r;

  end function hex;

  constant CLK_PERIOD            : time    := 10 ns;
  constant IN_WIDTH              : natural := 48;
  constant OUT_BYTES_PER_CYCLE   : natural := 4;
  constant BURST_DEPTH           : natural := CO_BYTE_STUFFER_BURST_DEPTH;
  constant OUT_WIDTH             : natural := OUT_BYTES_PER_CYCLE * 8;

  signal iClk                    : std_logic;
  signal iRst                    : std_logic;
  signal iStall                  : std_logic;
  signal iReady                  : std_logic;
  signal iFlush                  : std_logic;
  signal iWordValid              : std_logic;
  signal iWord                   : std_logic_vector(IN_WIDTH - 1 downto 0);
  signal iValidLen               : unsigned(log2ceil(IN_WIDTH + 1) - 1 downto 0);
  signal oWord                   : std_logic_vector(OUT_WIDTH - 1 downto 0);
  signal oWordValid              : std_logic;
  signal oValidBytes             : unsigned(log2ceil(OUT_BYTES_PER_CYCLE + 1) - 1 downto 0);
  signal oAlmostFull             : std_logic;
  signal oFlushDone              : std_logic;

  type byte_array_t is array(natural range <>) of std_logic_vector(7 downto 0);

  constant COLLECT_CAP           : natural := 4096;

  -- Collector shared state. Reset (collectedCount <= 0) is requested by the
  -- stimulus process via `collectResetReq`; collector clears its counters
  -- on the next rising edge and pulses `collectResetAck`.
  shared variable collected      : byte_array_t(0 to COLLECT_CAP - 1);
  shared variable collectedCount : natural;
  shared variable flushDoneCount : natural;

  signal collectResetReq         : std_logic;
  signal collectResetAck         : std_logic;

begin

  clk_proc : process is
  begin

    iClk <= '0';
    wait for CLK_PERIOD / 2;
    iClk <= '1';
    wait for CLK_PERIOD / 2;

  end process clk_proc;

  dut : entity work.byte_stuffer(behavioral)

    generic map (
      IN_WIDTH            => IN_WIDTH,
      OUT_BYTES_PER_CYCLE => OUT_BYTES_PER_CYCLE,
      BURST_DEPTH         => BURST_DEPTH
    )
    port map (
      iClk                => iClk,
      iRst                => iRst,
      iStall              => iStall,
      iFlush              => iFlush,
      iWord               => iWord,
      iWordValid          => iWordValid,
      iValidLen           => iValidLen,
      oWord               => oWord,
      oWordValid          => oWordValid,
      oValidBytes         => oValidBytes,
      iReady              => iReady,
      oAlmostFull         => oAlmostFull,
      oFlushDone          => oFlushDone
    );

  ----------------------------------------------------------------------------
  -- Collector: capture output bytes on every cycle oWordValid='1'. Uses the
  -- oValidBytes count to know how many top bytes of oWord are payload (MSB
  -- = first byte). Counters cleared on iRst and on collectResetReq pulses
  -- from the stimulus process between tests.
  ----------------------------------------------------------------------------
  collect : process (iClk) is

    variable n : natural;

  begin

    if rising_edge(iClk) then
      collectResetAck <= '0';
      if (iRst = '1') then
        collectedCount := 0;
        flushDoneCount := 0;
      else
        if (collectResetReq = '1') then
          collectedCount  := 0;
          flushDoneCount  := 0;
          collectResetAck <= '1';
        end if;

        if (oWordValid = '1') then
          n := to_integer(oValidBytes);

          for i in 0 to OUT_BYTES_PER_CYCLE - 1 loop

            if (i < n) then
              if (collectedCount < COLLECT_CAP) then
                collected(collectedCount) := oWord(OUT_WIDTH - 1 - i * 8
                                                   downto OUT_WIDTH - (i + 1) * 8);
              end if;
              collectedCount := collectedCount + 1;
            end if;

          end loop;

        end if;

        if (oFlushDone = '1') then
          flushDoneCount := flushDoneCount + 1;
        end if;
      end if;
    end if;

  end process collect;

  ----------------------------------------------------------------------------
  -- Stimulus
  ----------------------------------------------------------------------------
  stim : process is

    procedure clear_collector is
    begin

      -- Reset idle-side signals then handshake with collect process.
      -- iRst is NOT asserted here — do_reset handles DUT reset.
      iStall          <= '0';
      iFlush          <= '0';
      iWordValid      <= '0';
      iWord           <= (others => '0');
      iValidLen       <= (others => '0');

      collectResetReq <= '1';
      wait until rising_edge(iClk) and collectResetAck = '1';
      collectResetReq <= '0';
      wait until rising_edge(iClk);

    end procedure clear_collector;

    procedure do_reset is
    begin

      iRst       <= '1';
      iWordValid <= '0';
      iFlush     <= '0';
      iStall     <= '0';

      for i in 0 to 3 loop

        wait until rising_edge(iClk);

      end loop;

      iRst <= '0';
      wait until rising_edge(iClk);

    end procedure do_reset;

    -- Drive one input word. `last` asserts iFlush together with
    -- iWordValid on this beat, matching the top-level convention
    -- (sBsFlush <= sReg6EOI registered alongside bit_packer's last word).

    procedure send_word (
      constant word : in std_logic_vector(IN_WIDTH - 1 downto 0);
      constant vlen : in natural;
      constant last : in boolean := false
    ) is
    begin

      iWordValid <= '1';
      iWord      <= word;
      iValidLen  <= to_unsigned(vlen, iValidLen'length);

      if (last) then
        iFlush <= '1';
      else
        iFlush <= '0';
      end if;

      wait until rising_edge(iClk);
      iWordValid <= '0';
      iFlush     <= '0';
      iValidLen  <= (others => '0');

    end procedure send_word;

    -- Wait for oFlushDone, with timeout.

    procedure wait_flush_done (
      constant tag : in string
    ) is

      variable cycles : natural;

    begin

      while flushDoneCount = 0 loop

        wait until rising_edge(iClk);
        cycles := cycles + 1;

        if (cycles >= 500) then
          report tag & ": oFlushDone timeout after 500 cycles"
            severity error;
          errCount := errCount + 1;
          exit;
        end if;

      end loop;

      -- Drain a few extra cycles to make sure no stray output leaks past
      -- oFlushDone.
      for i in 0 to 3 loop

        wait until rising_edge(iClk);

      end loop;

    end procedure wait_flush_done;

    procedure check_output (
      constant expected : in byte_array_t;
      constant tag      : in string
    ) is

      variable n : natural;

    begin

      check(collectedCount = expected'length,
            tag & ": byte count mismatch exp=" & integer'image(expected'length) &
            " got=" & integer'image(collectedCount));
      n := collectedCount;

      if (expected'length < n) then
        n := expected'length;
      end if;

      for i in 0 to n - 1 loop

        check(collected(i) = expected(expected'low + i),
              tag & ": byte " & integer'image(i) &
              " exp=0x" & hex(expected(expected'low + i)) &
              " got=0x" & hex(collected(i)));

      end loop;

      check(flushDoneCount = 1,
            tag & ": expected exactly one oFlushDone pulse, got " &
            integer'image(flushDoneCount));

    end procedure check_output;

  begin

    -- Initial values (no defaults — set explicitly at top of stim)
    iReady <= '1';

    -- ------------------------------------------------------------------
    -- T1: pure pass-through, no 0xFF in stream, byte-aligned input.
    --   Bytes:  12 34 56 78 9A BC  -> identical on output, no pad.
    -- ------------------------------------------------------------------
    do_reset;
    send_word(x"123456789ABC", 48, last => true);
    wait_flush_done("T1");
    check_output((x"12", x"34", x"56", x"78", x"9A", x"BC"), "T1");

    -- ------------------------------------------------------------------
    -- T2: leading 0xFF triggers a stuff bit; remaining bytes shift right
    -- by 1 bit. Trailing 1-bit residue padded to a final 0x00 byte.
    --   In bits:  11111111 10000000 01000000 00100000 00010000 00001000
    --   B0 = FF (prev_FF=1)
    --   B1 = '0' + next 7 bits = 0_1000000 = 0x40
    --   B2 = bits[15..22]      = 0_0100000 = 0x20
    --   B3 = bits[23..30]      = 0_0010000 = 0x10
    --   B4 = bits[31..38]      = 0_0001000 = 0x08
    --   B5 = bits[39..46]      = 0_0000100 = 0x04
    --   B6 = pad of last bit + 7 zeros = 0x00
    -- ------------------------------------------------------------------
    do_reset;
    clear_collector;
    send_word(x"FF8040201008", 48, last => true);
    wait_flush_done("T2");
    check_output((x"FF", x"40", x"20", x"10", x"08", x"04", x"00"), "T2");

    -- ------------------------------------------------------------------
    -- T3: trailing 0xFF. Stuff bit + zero pad land in the flush byte.
    --   Bytes:  80 40 20 10 08 FF   (last byte FF -> prev_FF latched
    --   at end-of-stream -> final byte = stuff '0' + 7 zeros = 0x00)
    -- ------------------------------------------------------------------
    do_reset;
    clear_collector;
    send_word(x"8040201008FF", 48, last => true);
    wait_flush_done("T3");
    check_output((x"80", x"40", x"20", x"10", x"08", x"FF", x"00"), "T3");

    -- ------------------------------------------------------------------
    -- T4: two adjacent FF input bytes — only the FIRST is an output FF;
    -- the second becomes 0x7F (with stuff bit prepended) and does not
    -- trigger another stuff.
    --   In bits:  11111111 11111111 00000000 00000000 00000000 00000000
    --   B0 = FF
    --   B1 = 0 + 1111111 = 0x7F
    --   B2 = bits[15..22] = 1_0000000 = 0x80
    --   B3 = bits[23..30] = 0_0000000 = 0x00
    --   B4 = bits[31..38] = 0x00
    --   B5 = bits[39..46] = 0x00
    --   B6 = pad final 1 bit (=0) + zeros = 0x00
    -- ------------------------------------------------------------------
    do_reset;
    clear_collector;
    send_word(x"FFFF00000000", 48, last => true);
    wait_flush_done("T4");
    check_output((x"FF", x"7F", x"80", x"00", x"00", x"00", x"00"), "T4");

    -- ------------------------------------------------------------------
    -- T5: all-ones (48 bits). Three output FF / 7F pairs; 3-bit residue
    -- gets padded to 0xE0.
    -- ------------------------------------------------------------------
    do_reset;
    clear_collector;
    send_word(x"FFFFFFFFFFFF", 48, last => true);
    wait_flush_done("T5");
    check_output((x"FF", x"7F", x"FF", x"7F", x"FF", x"7F", x"E0"), "T5");

    -- ------------------------------------------------------------------
    -- T6: FF byte forms ACROSS the input-word boundary — exercises Stage
    -- 1's bit accumulator carrying residue into the next FIFO push, and
    -- Stage 3's output-side FF detection on bits spanning multiple FIFO
    -- pops.
    --   Inputs (96 bits total):
    --     w0 = FF 00 00 00 00 01,  w1 = FE FF 00 00 00 00
    --   After byte 6 (formed from FF 00..00 01 spanning into FE), the
    --   output stream contains a second FF, producing a second stuff.
    --   Expected: FF 00 00 00 00 00 FF 3F C0 00 00 00 00 (13 bytes,
    --   final 2 bits of residue padded).
    -- ------------------------------------------------------------------
    do_reset;
    clear_collector;
    send_word(x"FF0000000001", 48);
    send_word(x"FEFF00000000", 48, last => true);
    wait_flush_done("T6");
    check_output((x"FF", x"00", x"00", x"00", x"00", x"00",
                  x"FF", x"3F", x"C0", x"00", x"00", x"00", x"00"), "T6");

    -- ------------------------------------------------------------------
    -- T7: short word — iValidLen smaller than IN_WIDTH. Sub-byte residue
    -- carries between words. Final flush pads to a byte.
    --   Send (12 bits) 0xABC, then (12 bits) 0xDEF. The valid bits sit at
    --   the MSB end of iWord (bit_packer convention), so they're encoded
    --   as 0xABC0_0000_0000 and 0xDEF0_0000_0000.
    --   Concatenated MSB-first: 1010_1011_1100_1101_1110_1111 (24 bits)
    --   = bytes AB CD EF. No FF in stream. No pad needed (24 bits = 3 B).
    -- ------------------------------------------------------------------
    do_reset;
    clear_collector;
    send_word(x"ABC000000000", 12);
    send_word(x"DEF000000000", 12, last => true);
    wait_flush_done("T7");
    check_output((x"AB", x"CD", x"EF"), "T7");

    -- ------------------------------------------------------------------
    -- T8: stall mid-stream. iStall held for several cycles after the
    -- last word + flush. No byte should be dropped; final flush should
    -- still complete once iStall releases. Same expected output as T5.
    -- ------------------------------------------------------------------
    do_reset;
    clear_collector;
    send_word(x"FFFFFFFFFFFF", 48, last => true);
    iStall <= '1';

    for i in 0 to 6 loop

      wait until rising_edge(iClk);

    end loop;

    iStall <= '0';
    wait_flush_done("T8");
    check_output((x"FF", x"7F", x"FF", x"7F", x"FF", x"7F", x"E0"), "T8");

    -- ------------------------------------------------------------------
    -- T9: back-to-back images. Reset between feeds (full pipeline reset
    -- so collector counters reset together). Each image flushes
    -- independently and produces its own oFlushDone pulse.
    -- ------------------------------------------------------------------
    do_reset;
    clear_collector;
    send_word(x"123456789ABC", 48, last => true);
    wait_flush_done("T9a");
    check_output((x"12", x"34", x"56", x"78", x"9A", x"BC"), "T9a");

    clear_collector;
    send_word(x"FF8040201008", 48, last => true);
    wait_flush_done("T9b");
    check_output((x"FF", x"40", x"20", x"10", x"08", x"04", x"00"), "T9b");

    -- ------------------------------------------------------------------
    -- Final report
    -- ------------------------------------------------------------------
    wait for CLK_PERIOD * 2;

    if (errCount > 0) then
      report "tb_byte_stuffer RESULT: FAIL (" & integer'image(errCount) & " errors)"
        severity failure;
    else
      report "tb_byte_stuffer RESULT: PASS"
        severity note;
    end if;

    finish;

  end process stim;

end architecture bench;
