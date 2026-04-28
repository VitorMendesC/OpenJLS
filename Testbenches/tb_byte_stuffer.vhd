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

  -- to_integer(unsigned(...)) overflows VHDL integer for >32-bit vectors,
  -- so build hex strings nibble-by-nibble for diagnostic messages.
  function slv2hex(v : std_logic_vector) return string is
    constant HEX    : string(1 to 16) := "0123456789ABCDEF";
    variable nibs   : natural          := (v'length + 3) / 4;
    variable padded : std_logic_vector(nibs * 4 - 1 downto 0) := (others => '0');
    variable r      : string(1 to nibs);
  begin
    padded(v'length - 1 downto 0) := v;
    for i in 0 to nibs - 1 loop
      r(nibs - i) := HEX(to_integer(unsigned(padded(i * 4 + 3 downto i * 4))) + 1);
    end loop;
    return r;
  end function;

  constant CLK_PERIOD   : time    := 10 ns;
  constant IN_WIDTH     : natural := 48; -- CO_LIMIT_STD for BITNESS=12
  constant OUT_WIDTH    : natural := 64; -- CO_BYTE_STUFFER_OUT_WIDTH
  constant BUFFER_WIDTH : natural := 2 * IN_WIDTH + IN_WIDTH / 8;

  signal iClk        : std_logic                                     := '0';
  signal iRst        : std_logic                                     := '0';
  signal iFlush      : std_logic                                     := '0';
  signal iWordValid  : std_logic                                     := '0';
  signal iWord       : std_logic_vector(IN_WIDTH - 1 downto 0)       := (others => '0');
  signal iValidLen   : unsigned(log2ceil(IN_WIDTH + 1) - 1 downto 0) := (others => '0');
  signal oWord       : std_logic_vector(OUT_WIDTH - 1 downto 0);
  signal oWordValid  : std_logic;
  signal oValidBytes : unsigned(log2ceil(OUT_WIDTH / 8 + 1) - 1 downto 0);

  type word48_array_t is array (natural range <>) of std_logic_vector(47 downto 0);
  type word64_array_t is array (natural range <>) of std_logic_vector(63 downto 0);

  -- T1: no 0xFF — pass-through. 6 input bytes -> 6 valid output bytes + 2 zero pad.
  constant C_IN_T1  : word48_array_t := (x"123456789ABC", x"DEF012345678");
  constant C_EXP_T1 : word64_array_t := (x"123456789ABC0000", x"DEF0123456780000");

  -- T2: 0xFF first byte — stuff bit shifts following bytes by 1.
  -- Stream bytes: FF 40 20 10 08 04, residue '0' (1 bit).
  constant C_IN_T2    : word48_array_t                           := (0      => x"FF8040201008");
  constant C_EXP_T2   : word64_array_t                           := (0      => x"FF40201008040000");
  constant C_FLUSH_T2 : std_logic_vector(OUT_WIDTH - 1 downto 0) := (others => '0');

  -- T3: 0xFF last byte — output unchanged, stuff bit lands in flush.
  constant C_IN_T3    : word48_array_t                           := (0      => x"8040201008FF");
  constant C_EXP_T3   : word64_array_t                           := (0      => x"8040201008FF0000");
  constant C_FLUSH_T3 : std_logic_vector(OUT_WIDTH - 1 downto 0) := (others => '0');

  -- T4: two 0xFF in one word.
  -- Stream bytes: FF 7F 80 00 00 00, residue '0'.
  constant C_IN_T4    : word48_array_t                           := (0      => x"FFFF00000000");
  constant C_EXP_T4   : word64_array_t                           := (0      => x"FF7F800000000000");
  constant C_FLUSH_T4 : std_logic_vector(OUT_WIDTH - 1 downto 0) := (others => '0');

  -- T5: stranded bit = '1' distinguishes real bit from zero-padding.
  -- Like T2 but final input byte = 0x09, so residue is '1'. The residue is
  -- visible in output byte 6 = 0x80 because OUT_WIDTH (8 bytes) > emitted
  -- bytes (6); the unemitted top of vBuf is captured before shift.
  constant C_IN_T5    : word48_array_t                           := (0 => x"FF8040201009");
  constant C_EXP_T5   : word64_array_t                           := (0 => x"FF40201008048000");
  constant C_FLUSH_T5 : std_logic_vector(OUT_WIDTH - 1 downto 0) := x"8000000000000000";

  -- T6: 48 consecutive '1' bits — distinguishes correct stuffing (interp A,
  -- stuffed bit becomes MSB of next stream byte) from a pre-stuffing logical
  -- byte counter (interp B). Correct stream: FF 7F FF 7F FF 7F + 3-bit
  -- residue 111 (visible in output byte 6 = 0xE0). A buggy old behaviour
  -- would stuff every 8 input bits regardless of stream byte content,
  -- producing FF 7F BF DF EF F7 + 6-bit residue.
  constant C_IN_T6    : word48_array_t                           := (0 => x"FFFFFFFFFFFF");
  constant C_EXP_T6   : word64_array_t                           := (0 => x"FF7FFF7FFF7FE000");
  constant C_FLUSH_T6 : std_logic_vector(OUT_WIDTH - 1 downto 0) := x"E000000000000000";

  -- T7: 0xFF byte spanning word boundary — exercises sByteReg/sBytePos carry.
  -- Word 1 stuffs at bit 7, leaving residue '1' in the buffer with vBPos=1.
  -- Word 2's first 7 bits combine with that residue to form stream byte 7
  -- = 0xFF, triggering a second stuff. Without correct cross-word tracker
  -- state, the second stuff is missed and bytes 9.. shift, producing a
  -- visibly different word 2 (correct: FF 3F C0 .., buggy: FF 7F 80 ..).
  constant C_IN_T7    : word48_array_t                           := (x"FF0000000001", x"FEFF00000000");
  constant C_EXP_T7   : word64_array_t                           := (x"FF00000000008000", x"FF3FC00000000000");
  constant C_FLUSH_T7 : std_logic_vector(OUT_WIDTH - 1 downto 0) := (others => '0');

begin
  iClk <= not iClk after CLK_PERIOD / 2;

  dut : entity work.byte_stuffer
    generic map(
      IN_WIDTH     => IN_WIDTH,
      OUT_WIDTH    => OUT_WIDTH,
      BUFFER_WIDTH => BUFFER_WIDTH
    )
    port map
    (
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
      word     : std_logic_vector(IN_WIDTH - 1 downto 0);
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
      " exp=0x" & slv2hex(exp_word) &
      " got=0x" & slv2hex(oWord));
      check(oValidBytes = to_unsigned(IN_WIDTH / 8, oValidBytes'length),
      tag & ": oValidBytes wrong at index " & integer'image(idx));
    end procedure;

    procedure do_flush(
      exp_valid  : boolean;
      exp_word   : std_logic_vector(OUT_WIDTH - 1 downto 0);
      exp_vbytes : natural;
      tag        : string
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
        tag & ": flush word mismatch exp=0x" & slv2hex(exp_word) &
        " got=0x" & slv2hex(oWord));
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

    iRst <= '1';
    wait until rising_edge(iClk);
    wait until rising_edge(iClk);
    iRst <= '0';

    ----------------------------------------------------------------------------
    -- T2: 0xFF first byte
    ----------------------------------------------------------------------------
    for i in C_IN_T2'range loop
      send_and_check(C_IN_T2(i), C_EXP_T2(i), "T2", i);
    end loop;
    do_flush(true, C_FLUSH_T2, 1, "T2");

    iRst <= '1';
    wait until rising_edge(iClk);
    wait until rising_edge(iClk);
    iRst <= '0';

    ----------------------------------------------------------------------------
    -- T3: 0xFF last byte
    ----------------------------------------------------------------------------
    for i in C_IN_T3'range loop
      send_and_check(C_IN_T3(i), C_EXP_T3(i), "T3", i);
    end loop;
    do_flush(true, C_FLUSH_T3, 1, "T3");

    iRst <= '1';
    wait until rising_edge(iClk);
    wait until rising_edge(iClk);
    iRst <= '0';

    ----------------------------------------------------------------------------
    -- T4: two 0xFF in one word
    ----------------------------------------------------------------------------
    for i in C_IN_T4'range loop
      send_and_check(C_IN_T4(i), C_EXP_T4(i), "T4", i);
    end loop;
    do_flush(true, C_FLUSH_T4, 1, "T4");

    iRst <= '1';
    wait until rising_edge(iClk);
    wait until rising_edge(iClk);
    iRst <= '0';

    ----------------------------------------------------------------------------
    -- T5: stranded bit = '1'
    ----------------------------------------------------------------------------
    for i in C_IN_T5'range loop
      send_and_check(C_IN_T5(i), C_EXP_T5(i), "T5", i);
    end loop;
    do_flush(true, C_FLUSH_T5, 1, "T5");

    iRst <= '1';
    wait until rising_edge(iClk);
    wait until rising_edge(iClk);
    iRst <= '0';

    ----------------------------------------------------------------------------
    -- T6: all-ones — divergence between interp A (correct) and interp B (buggy)
    ----------------------------------------------------------------------------
    for i in C_IN_T6'range loop
      send_and_check(C_IN_T6(i), C_EXP_T6(i), "T6", i);
    end loop;
    do_flush(true, C_FLUSH_T6, 1, "T6");

    iRst <= '1';
    wait until rising_edge(iClk);
    wait until rising_edge(iClk);
    iRst <= '0';

    ----------------------------------------------------------------------------
    -- T7: 0xFF spanning word boundary — exercises cross-word tracker state
    ----------------------------------------------------------------------------
    for i in C_IN_T7'range loop
      send_and_check(C_IN_T7(i), C_EXP_T7(i), "T7", i);
    end loop;
    do_flush(true, C_FLUSH_T7, 1, "T7");

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
