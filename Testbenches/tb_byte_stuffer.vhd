library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library openlogic_base;
use openlogic_base.olo_base_pkg_math.log2ceil;

use std.env.all;

entity tb_byte_stuffer is
end;

architecture bench of tb_byte_stuffer is
  shared variable err_count : natural := 0;

  procedure check(cond : boolean; msg : string) is
  begin
    if not cond then
      report msg severity error;
      err_count := err_count + 1;
    end if;
  end procedure;

  constant CLK_PERIOD   : time    := 10 ns;
  constant IN_WIDTH     : natural := 24; -- 3 bytes: guaranteed no stall (actual data ≤ 2 bytes/cycle)
  constant OUT_WIDTH    : natural := 24;
  constant BUFFER_WIDTH : natural := 2 * IN_WIDTH + IN_WIDTH / 8; -- 51

  signal iClk        : std_logic := '0';
  signal iRst        : std_logic := '0';
  signal iFlush      : std_logic := '0';
  signal iValid      : std_logic := '0';
  signal iWord       : std_logic_vector(IN_WIDTH  - 1 downto 0) := (others => '0');
  signal oReady      : std_logic;
  signal oWord       : std_logic_vector(OUT_WIDTH - 1 downto 0);
  signal oWordValid  : std_logic;
  signal oValidBytes : unsigned(log2ceil(OUT_WIDTH / 8) downto 0);
  signal iReady      : std_logic := '1';

  type word24_array_t is array (natural range <>) of std_logic_vector(23 downto 0);

  -- Test 1: no 0xFF bytes — output equals input, buffer empty after each word
  constant C_IN_T1  : word24_array_t := (x"123456", x"ABCDEF");
  constant C_EXP_T1 : word24_array_t := (x"123456", x"ABCDEF");

  -- Test 2: 0xFF as first byte of a 3-byte word (0xFF 0x80 0x40)
  --   Stream after stuffing: "11111111" "0" "10000000" "01000000" = 25 bits
  --   Output (bits 0-23): "11111111" "01000000" "00100000" = 0xFF 0x40 0x20
  --   Flush  (bit 24):    "0" + 7 zeros → 0x00, oValidBytes=1
  constant C_IN_T2    : word24_array_t := (0 => x"FF8040");
  constant C_EXP_T2   : word24_array_t := (0 => x"FF4020");
  constant C_FLUSH_T2 : std_logic_vector(OUT_WIDTH - 1 downto 0) := x"000000";

  -- Test 3: 0xFF as last byte of a 3-byte word (0x80 0x40 0xFF)
  --   Stream after stuffing: "10000000" "01000000" "11111111" "0" = 25 bits
  --   Output (bits 0-23): "10000000" "01000000" "11111111" = 0x80 0x40 0xFF
  --   Flush  (bit 24):    "0" + 7 zeros → 0x00, oValidBytes=1
  constant C_IN_T3    : word24_array_t := (0 => x"8040FF");
  constant C_EXP_T3   : word24_array_t := (0 => x"8040FF");
  constant C_FLUSH_T3 : std_logic_vector(OUT_WIDTH - 1 downto 0) := x"000000";

  -- Test 4: two 0xFF bytes in one word (0xFF 0xFF 0x00)
  --   Stream after stuffing: "11111111" "0" "11111111" "0" "00000000" = 26 bits
  --   Output (bits 0-23): "11111111" "01111111" "10000000" = 0xFF 0x7F 0x80
  --   Flush  (bits 24-25): "00" + 6 zeros → 0x00, oValidBytes=1
  constant C_IN_T4    : word24_array_t := (0 => x"FFFF00");
  constant C_EXP_T4   : word24_array_t := (0 => x"FF7F80");
  constant C_FLUSH_T4 : std_logic_vector(OUT_WIDTH - 1 downto 0) := x"000000";

  -- Test 5: 0xFF as first byte, last data bit = '1' (0xFF 0x80 0x41)
  --   Same stuffed stream as T2 except final bit: "11111111" "0" "10000000" "01000001"
  --   Output (bits 0-23): identical to T2 → 0xFF 0x40 0x20
  --   Flush  (bit 24):    "1" (last bit of 0x41) + 7 zeros → 0x80, oValidBytes=1
  --   Distinguishes the real stranded data bit from zero-padding
  constant C_IN_T5    : word24_array_t := (0 => x"FF8041");
  constant C_EXP_T5   : word24_array_t := (0 => x"FF4020");
  constant C_FLUSH_T5 : std_logic_vector(OUT_WIDTH - 1 downto 0) := x"800000";

begin
  iClk <= not iClk after CLK_PERIOD / 2;

  dut : entity work.byte_stuffer
    generic map(
      IN_WIDTH     => IN_WIDTH,
      OUT_WIDTH    => OUT_WIDTH,
      BUFFER_WIDTH => BUFFER_WIDTH
    )
    port map(
      iClk        => iClk,
      iRst        => iRst,
      iFlush      => iFlush,
      iValid      => iValid,
      iWord       => iWord,
      oReady      => oReady,
      oWord       => oWord,
      oWordValid  => oWordValid,
      oValidBytes => oValidBytes,
      iReady      => iReady
    );

  stim : process
    procedure send_and_check(
      word     : std_logic_vector(IN_WIDTH  - 1 downto 0);
      exp_word : std_logic_vector(OUT_WIDTH - 1 downto 0);
      tag      : string;
      idx      : natural
    ) is
    begin
      iValid <= '1';
      iWord  <= word;
      wait until rising_edge(iClk);
      wait for 1 ns;
      check(oReady = '1',     tag & ": oReady deasserted at index " & integer'image(idx));
      check(oWordValid = '1', tag & ": oWordValid not asserted at index " & integer'image(idx));
      check(oWord = exp_word,
        tag & ": mismatch at index " & integer'image(idx) &
        " exp=0x" & integer'image(to_integer(unsigned(exp_word))) &
        " got=0x" & integer'image(to_integer(unsigned(oWord))));
      check(oValidBytes = to_unsigned(OUT_WIDTH / 8, oValidBytes'length),
        tag & ": oValidBytes wrong at index " & integer'image(idx));
    end procedure;

    procedure do_flush(
      exp_valid    : boolean;
      exp_word     : std_logic_vector(OUT_WIDTH - 1 downto 0);
      exp_vbytes   : natural;
      tag          : string
    ) is
    begin
      iValid <= '0';
      iFlush <= '1';
      wait until rising_edge(iClk);
      wait for 1 ns;
      check(oReady = '0', tag & ": oReady should be deasserted during flush");
      if exp_valid then
        check(oWordValid = '1', tag & ": flush word not emitted");
        check(oWord = exp_word,
          tag & ": flush word mismatch exp=0x" & integer'image(to_integer(unsigned(exp_word))) &
          " got=0x" & integer'image(to_integer(unsigned(oWord))));
        check(oValidBytes = to_unsigned(exp_vbytes, oValidBytes'length),
          tag & ": flush oValidBytes exp=" & integer'image(exp_vbytes) &
          " got=" & integer'image(to_integer(oValidBytes)));
      end if;
      iFlush <= '0';
      wait until rising_edge(iClk);
      wait for 1 ns;
      check(oWordValid = '0', tag & ": oWordValid should deassert after flush handshake");
    end procedure;

  begin

    -- Initial reset
    iRst   <= '1';
    iValid <= '0';
    iFlush <= '0';
    iReady <= '1';
    wait until rising_edge(iClk);
    wait until rising_edge(iClk);
    iRst <= '0';

    ----------------------------------------------------------------------------
    -- Test 1: no 0xFF — pass-through, buffer empty after each aligned word
    ----------------------------------------------------------------------------
    for i in C_IN_T1'range loop
      send_and_check(C_IN_T1(i), C_EXP_T1(i), "T1", i);
    end loop;
    do_flush(false, (others => '0'), 0, "T1");

    iRst <= '1'; wait until rising_edge(iClk); wait until rising_edge(iClk); iRst <= '0';

    ----------------------------------------------------------------------------
    -- Test 2: 0xFF as first byte — stuffing bit shifts remaining 2 bytes right by 1
    ----------------------------------------------------------------------------
    for i in C_IN_T2'range loop
      send_and_check(C_IN_T2(i), C_EXP_T2(i), "T2", i);
    end loop;
    do_flush(true, C_FLUSH_T2, 1, "T2");

    iRst <= '1'; wait until rising_edge(iClk); wait until rising_edge(iClk); iRst <= '0';

    ----------------------------------------------------------------------------
    -- Test 3: 0xFF as last byte — output word unchanged, stuffing bit in flush byte
    ----------------------------------------------------------------------------
    for i in C_IN_T3'range loop
      send_and_check(C_IN_T3(i), C_EXP_T3(i), "T3", i);
    end loop;
    do_flush(true, C_FLUSH_T3, 1, "T3");

    iRst <= '1'; wait until rising_edge(iClk); wait until rising_edge(iClk); iRst <= '0';

    ----------------------------------------------------------------------------
    -- Test 4: two 0xFF in one word — two independent stuffing bits
    ----------------------------------------------------------------------------
    for i in C_IN_T4'range loop
      send_and_check(C_IN_T4(i), C_EXP_T4(i), "T4", i);
    end loop;
    do_flush(true, C_FLUSH_T4, 1, "T4");

    iRst <= '1'; wait until rising_edge(iClk); wait until rising_edge(iClk); iRst <= '0';

    ----------------------------------------------------------------------------
    -- Test 5: stranded bit = '1' — flush output is 0x80, not 0x00
    ----------------------------------------------------------------------------
    for i in C_IN_T5'range loop
      send_and_check(C_IN_T5(i), C_EXP_T5(i), "T5", i);
    end loop;
    do_flush(true, C_FLUSH_T5, 1, "T5");

    ----------------------------------------------------------------------------
    -- Result
    ----------------------------------------------------------------------------
    if err_count > 0 then
      report "tb_byte_stuffer RESULT: FAIL (" & integer'image(err_count) & " errors)" severity failure;
    else
      report "tb_byte_stuffer RESULT: PASS" severity note;
    end if;
    finish;
  end process;

end;
