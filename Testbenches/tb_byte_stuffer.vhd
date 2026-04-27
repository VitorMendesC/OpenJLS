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
  constant IN_WIDTH     : natural := 24;
  constant OUT_WIDTH    : natural := 24;
  constant BUFFER_WIDTH : natural := 2 * IN_WIDTH + IN_WIDTH / 8;

  signal iClk        : std_logic := '0';
  signal iRst        : std_logic := '0';
  signal iFlush      : std_logic := '0';
  signal iWordValid  : std_logic := '0';
  signal iWord       : std_logic_vector(IN_WIDTH - 1 downto 0) := (others => '0');
  signal iValidLen   : unsigned(log2ceil(IN_WIDTH + 1) - 1 downto 0) := (others => '0');
  signal oWord       : std_logic_vector(OUT_WIDTH - 1 downto 0);
  signal oWordValid  : std_logic;
  signal oValidBytes : unsigned(log2ceil(OUT_WIDTH / 8 + 1) - 1 downto 0);

  type word24_array_t is array (natural range <>) of std_logic_vector(23 downto 0);

  -- T1: no 0xFF — pass-through
  constant C_IN_T1  : word24_array_t := (x"123456", x"ABCDEF");
  constant C_EXP_T1 : word24_array_t := (x"123456", x"ABCDEF");

  -- T2: 0xFF first byte — stuff bit shifts following bytes by 1
  constant C_IN_T2    : word24_array_t := (0 => x"FF8040");
  constant C_EXP_T2   : word24_array_t := (0 => x"FF4020");
  constant C_FLUSH_T2 : std_logic_vector(OUT_WIDTH - 1 downto 0) := x"000000";

  -- T3: 0xFF last byte — output unchanged, stuff bit lands in flush
  constant C_IN_T3    : word24_array_t := (0 => x"8040FF");
  constant C_EXP_T3   : word24_array_t := (0 => x"8040FF");
  constant C_FLUSH_T3 : std_logic_vector(OUT_WIDTH - 1 downto 0) := x"000000";

  -- T4: two 0xFF in one word
  constant C_IN_T4    : word24_array_t := (0 => x"FFFF00");
  constant C_EXP_T4   : word24_array_t := (0 => x"FF7F80");
  constant C_FLUSH_T4 : std_logic_vector(OUT_WIDTH - 1 downto 0) := x"000000";

  -- T5: stranded bit = '1' distinguishes real bit from zero-padding
  constant C_IN_T5    : word24_array_t := (0 => x"FF8041");
  constant C_EXP_T5   : word24_array_t := (0 => x"FF4020");
  constant C_FLUSH_T5 : std_logic_vector(OUT_WIDTH - 1 downto 0) := x"800000";

  -- T6: 24 consecutive '1' bits — distinguishes correct stuffing (interp A,
  -- stuffed bit becomes MSB of next stream byte) from a pre-stuffing logical
  -- byte counter (interp B). Stream: FF 0 1111111 1 1111110 1 = 26 bits.
  -- Bytes: FF 7F FF (correct) vs FF 7F BF (buggy old behaviour).
  constant C_IN_T6    : word24_array_t := (0 => x"FFFFFF");
  constant C_EXP_T6   : word24_array_t := (0 => x"FF7FFF");
  constant C_FLUSH_T6 : std_logic_vector(OUT_WIDTH - 1 downto 0) := x"400000";

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
      iWord       => iWord,
      iWordValid  => iWordValid,
      iValidLen   => iValidLen,
      oWord       => oWord,
      oWordValid  => oWordValid,
      oValidBytes => oValidBytes
    );

  stim : process
    procedure send_and_check(
      word     : std_logic_vector(IN_WIDTH  - 1 downto 0);
      exp_word : std_logic_vector(OUT_WIDTH - 1 downto 0);
      tag      : string;
      idx      : natural
    ) is
    begin
      iWordValid <= '1';
      iWord      <= word;
      iValidLen  <= to_unsigned(IN_WIDTH, iValidLen'length);
      wait until rising_edge(iClk);
      wait for 1 ns;
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
      iWordValid <= '0';
      iValidLen  <= (others => '0');
      iFlush     <= '1';
      wait until rising_edge(iClk);
      wait for 1 ns;
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
      check(oWordValid = '0', tag & ": oWordValid should deassert after flush");
    end procedure;

  begin

    iRst       <= '1';
    iWordValid <= '0';
    iFlush     <= '0';
    wait until rising_edge(iClk);
    wait until rising_edge(iClk);
    iRst <= '0';

    ----------------------------------------------------------------------------
    -- T1: no 0xFF — pass-through
    ----------------------------------------------------------------------------
    for i in C_IN_T1'range loop
      send_and_check(C_IN_T1(i), C_EXP_T1(i), "T1", i);
    end loop;
    do_flush(false, (others => '0'), 0, "T1");

    iRst <= '1'; wait until rising_edge(iClk); wait until rising_edge(iClk); iRst <= '0';

    ----------------------------------------------------------------------------
    -- T2: 0xFF first byte
    ----------------------------------------------------------------------------
    for i in C_IN_T2'range loop
      send_and_check(C_IN_T2(i), C_EXP_T2(i), "T2", i);
    end loop;
    do_flush(true, C_FLUSH_T2, 1, "T2");

    iRst <= '1'; wait until rising_edge(iClk); wait until rising_edge(iClk); iRst <= '0';

    ----------------------------------------------------------------------------
    -- T3: 0xFF last byte
    ----------------------------------------------------------------------------
    for i in C_IN_T3'range loop
      send_and_check(C_IN_T3(i), C_EXP_T3(i), "T3", i);
    end loop;
    do_flush(true, C_FLUSH_T3, 1, "T3");

    iRst <= '1'; wait until rising_edge(iClk); wait until rising_edge(iClk); iRst <= '0';

    ----------------------------------------------------------------------------
    -- T4: two 0xFF in one word
    ----------------------------------------------------------------------------
    for i in C_IN_T4'range loop
      send_and_check(C_IN_T4(i), C_EXP_T4(i), "T4", i);
    end loop;
    do_flush(true, C_FLUSH_T4, 1, "T4");

    iRst <= '1'; wait until rising_edge(iClk); wait until rising_edge(iClk); iRst <= '0';

    ----------------------------------------------------------------------------
    -- T5: stranded bit = '1'
    ----------------------------------------------------------------------------
    for i in C_IN_T5'range loop
      send_and_check(C_IN_T5(i), C_EXP_T5(i), "T5", i);
    end loop;
    do_flush(true, C_FLUSH_T5, 1, "T5");

    iRst <= '1'; wait until rising_edge(iClk); wait until rising_edge(iClk); iRst <= '0';

    ----------------------------------------------------------------------------
    -- T6: all-ones — divergence between interp A (correct) and interp B (buggy)
    ----------------------------------------------------------------------------
    for i in C_IN_T6'range loop
      send_and_check(C_IN_T6(i), C_EXP_T6(i), "T6", i);
    end loop;
    do_flush(true, C_FLUSH_T6, 1, "T6");

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
