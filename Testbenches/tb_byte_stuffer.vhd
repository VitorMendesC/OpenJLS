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
  constant IN_WIDTH     : natural := 8;
  constant OUT_WIDTH    : natural := 8;
  constant BUFFER_WIDTH : natural := 2 * IN_WIDTH + IN_WIDTH / 8; -- 17

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

  type byte_array_t is array (natural range <>) of std_logic_vector(7 downto 0);

  -- Test 1: no 0xFF bytes — output equals input, buffer empty after last word (no flush output)
  constant C_IN_T1  : byte_array_t := (x"12", x"34", x"56", x"78");
  constant C_EXP_T1 : byte_array_t := (x"12", x"34", x"56", x"78");

  -- Test 2: 0xFF followed by 0x80
  --   Stuffed stream: "11111111" "0" "10000000" = 17 bits
  --   Output 1: "11111111"       = 0xFF  (8 bits)
  --   Output 2: "01000000"       = 0x40  (8 bits; stuffed '0' + 7 MSBs of 0x80)
  --   Flush:    "00000000"       = 0x00  (last bit of 0x80, zero-padded to 1 byte)
  constant C_IN_T2     : byte_array_t := (x"FF", x"80");
  constant C_EXP_T2    : byte_array_t := (x"FF", x"40");
  constant C_FLUSH_T2  : std_logic_vector(OUT_WIDTH - 1 downto 0) := x"00";

  -- Test 3: two consecutive 0xFF bytes followed by 0x00
  --   After 0xFF:  "11111111" "0"               count=9  → emit 0xFF,  leftover "0"      count=1
  --   After 0xFF:  "0" "11111111" "0"            count=10 → emit 0x7F,  leftover "10"     count=2
  --   After 0x00:  "10" "00000000"               count=10 → emit 0x80,  leftover "00"     count=2
  --   Flush:       "00000000"                             → 0x00, oValidBytes=1
  constant C_IN_T3     : byte_array_t := (x"FF", x"FF", x"00");
  constant C_EXP_T3    : byte_array_t := (x"FF", x"7F", x"80");
  constant C_FLUSH_T3  : std_logic_vector(OUT_WIDTH - 1 downto 0) := x"00";

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
    variable out_idx : natural := 0;

    -- Drive one data word, check expected output in the same clock cycle.
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

    -- Assert iFlush for one clock, verify output word and oValidBytes.
    procedure do_flush(
      exp_valid : boolean;
      exp_word  : std_logic_vector(OUT_WIDTH - 1 downto 0);
      tag       : string
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
        check(oValidBytes > 0, tag & ": oValidBytes should be > 0 on flush output");
      end if;
      iFlush <= '0';
      -- Allow the handshake to clear oWordValid
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
    -- Test 1: no 0xFF — output equals input, no flush output (buffer empty)
    ----------------------------------------------------------------------------
    for i in C_IN_T1'range loop
      send_and_check(C_IN_T1(i), C_EXP_T1(i), "T1", i);
    end loop;
    do_flush(false, (others => '0'), "T1");

    -- Reset between tests for clean state (sByteReg, sBytePos)
    iRst <= '1';
    wait until rising_edge(iClk);
    wait until rising_edge(iClk);
    iRst <= '0';

    ----------------------------------------------------------------------------
    -- Test 2: 0xFF followed by 0x80 — stuffing strands last bit, flushed as 0x00
    ----------------------------------------------------------------------------
    for i in C_IN_T2'range loop
      send_and_check(C_IN_T2(i), C_EXP_T2(i), "T2", i);
    end loop;
    do_flush(true, C_FLUSH_T2, "T2");

    -- Reset between tests
    iRst <= '1';
    wait until rising_edge(iClk);
    wait until rising_edge(iClk);
    iRst <= '0';

    ----------------------------------------------------------------------------
    -- Test 3: two consecutive 0xFF bytes — each stuffed independently
    ----------------------------------------------------------------------------
    for i in C_IN_T3'range loop
      send_and_check(C_IN_T3(i), C_EXP_T3(i), "T3", i);
    end loop;
    do_flush(true, C_FLUSH_T3, "T3");

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
