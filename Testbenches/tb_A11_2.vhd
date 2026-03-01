library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.env.all;

entity tb_A11_2 is
end;

architecture bench of tb_A11_2 is
  shared variable err_count : natural := 0;

  procedure check(cond : boolean; msg : string) is
  begin
    if not cond then
      report msg severity error;
      err_count := err_count + 1;
    end if;
  end procedure;

  constant CLK_PERIOD      : time    := 10 ns;
  constant LIMIT           : natural := 16;
  constant OUT_WIDTH       : natural := 8;
  constant BUFFER_WIDTH    : natural := 24;
  constant UNARY_WIDTH     : natural := 5;
  constant SUFFIX_WIDTH    : natural := 8;
  constant SUFFIXLEN_WIDTH : natural := 4;

  signal iClk            : std_logic := '0';
  signal iRst            : std_logic := '0';
  signal iFlush          : std_logic := '0';
  signal iRawMode        : std_logic := '0';
  signal iValid          : std_logic := '0';
  signal iUnaryZeros     : unsigned(UNARY_WIDTH - 1 downto 0) := (others => '0');
  signal iSuffixLen      : unsigned(SUFFIXLEN_WIDTH - 1 downto 0) := (others => '0');
  signal iSuffixVal      : unsigned(SUFFIX_WIDTH - 1 downto 0) := (others => '0');
  signal iReady          : std_logic := '1';
  signal oWord           : std_logic_vector(OUT_WIDTH - 1 downto 0);
  signal oWordValid      : std_logic;
  signal oBufferOverflow : std_logic;

  type int_array_t is array (natural range <>) of natural;
  constant C_UNARY      : int_array_t := (3, 0, 2, 0, 1, 0);
  constant C_SUFFIX_LEN : int_array_t := (4, 7, 2, 2, 1, 4);
  constant C_SUFFIX_VAL : int_array_t := (10, 85, 1, 2, 1, 9);

  type word_array_t is array (natural range <>) of std_logic_vector(OUT_WIDTH - 1 downto 0);
  constant C_EXP_WORDS : word_array_t := (x"1A", x"D5", x"2E", x"79");

  -- Raw mode test vectors (no unary prefix, no terminating '1').
  -- Case 1: len=4, val=0b0101=5   -> "0101"
  -- Case 2: len=4, val=0b1011=11  -> "1011"  => byte 0: "01011011" = 0x5B
  -- Case 3: len=3, val=0b010=2    -> "010"   (A16-style: prefix '0' + 2-bit RUNcnt)
  -- Case 4: len=5, val=0b11001=25 -> "11001" (A16-style: prefix '1' + 4-bit RUNcnt)
  --                                           => byte 1: "01011001" = 0x59
  constant C_RAW_LEN : int_array_t  := (4,   4,   3,   5);
  constant C_RAW_VAL : int_array_t  := (5,  11,   2,  25);
  constant C_EXP_RAW : word_array_t := (x"5B", x"59");
begin
  iClk <= not iClk after CLK_PERIOD / 2;

  dut : entity work.A11_2_bit_packer
    generic map(
      LIMIT           => LIMIT,
      OUT_WIDTH       => OUT_WIDTH,
      BUFFER_WIDTH    => BUFFER_WIDTH,
      UNARY_WIDTH     => UNARY_WIDTH,
      SUFFIX_WIDTH    => SUFFIX_WIDTH,
      SUFFIXLEN_WIDTH => SUFFIXLEN_WIDTH
    )
    port map(
      iClk            => iClk,
      iRst            => iRst,
      iFlush          => iFlush,
      iRawMode        => iRawMode,
      iValid          => iValid,
      iUnaryZeros     => iUnaryZeros,
      iSuffixLen      => iSuffixLen,
      iSuffixVal      => iSuffixVal,
      iReady          => iReady,
      oWord           => oWord,
      oWordValid      => oWordValid,
      oBufferOverflow => oBufferOverflow
    );

  stim : process
    variable out_idx : natural := 0;
  begin
    iRst   <= '1';
    iValid <= '0';
    iFlush <= '0';
    iReady <= '1';

    wait until rising_edge(iClk);
    wait until rising_edge(iClk);
    iRst <= '0';

    for cycle in 0 to 40 loop
      if cycle < C_UNARY'length then
        iValid      <= '1';
        iUnaryZeros <= to_unsigned(C_UNARY(cycle), iUnaryZeros'length);
        iSuffixLen  <= to_unsigned(C_SUFFIX_LEN(cycle), iSuffixLen'length);
        iSuffixVal  <= to_unsigned(C_SUFFIX_VAL(cycle), iSuffixVal'length);
      else
        iValid      <= '0';
        iUnaryZeros <= (others => '0');
        iSuffixLen  <= (others => '0');
        iSuffixVal  <= (others => '0');
      end if;

      wait until rising_edge(iClk);
      wait for 1 ns;

      if oWordValid = '1' then
        check(out_idx < C_EXP_WORDS'length,
          "A11.2 produced unexpected extra output word: " &
          integer'image(integer(out_idx))
        );

        check(oWord = C_EXP_WORDS(out_idx),
          "A11.2 output mismatch at index " &
          integer'image(integer(out_idx)) &
          " exp=" & integer'image(to_integer(unsigned(C_EXP_WORDS(out_idx)))) &
          " got=" & integer'image(to_integer(unsigned(oWord)))
        );

        out_idx := out_idx + 1;
      end if;
    end loop;

    check(out_idx = C_EXP_WORDS'length,
      "A11.2 output count mismatch. exp=" &
      integer'image(C_EXP_WORDS'length) &
      " got=" & integer'image(integer(out_idx))
    );

    check(oBufferOverflow = '0', "A11.2 Golomb: buffer overflow should not occur");

    -- Reset for raw mode test
    iRst   <= '1';
    iValid <= '0';
    wait until rising_edge(iClk);
    wait until rising_edge(iClk);
    iRst <= '0';

    -- Raw mode: append iSuffixLen bits of iSuffixVal with no Golomb framing
    out_idx := 0;
    for cycle in 0 to 20 loop
      if cycle < C_RAW_LEN'length then
        iRawMode   <= '1';
        iValid     <= '1';
        iSuffixLen <= to_unsigned(C_RAW_LEN(cycle), iSuffixLen'length);
        iSuffixVal <= to_unsigned(C_RAW_VAL(cycle), iSuffixVal'length);
      else
        iRawMode   <= '0';
        iValid     <= '0';
        iSuffixLen <= (others => '0');
        iSuffixVal <= (others => '0');
      end if;

      wait until rising_edge(iClk);
      wait for 1 ns;

      if oWordValid = '1' then
        check(out_idx < C_EXP_RAW'length,
          "A11.2 Raw: unexpected extra output word at index " &
          integer'image(integer(out_idx))
        );
        check(oWord = C_EXP_RAW(out_idx),
          "A11.2 Raw mismatch at index " & integer'image(integer(out_idx)) &
          " exp=" & integer'image(to_integer(unsigned(C_EXP_RAW(out_idx)))) &
          " got=" & integer'image(to_integer(unsigned(oWord)))
        );
        out_idx := out_idx + 1;
      end if;
    end loop;

    check(out_idx = C_EXP_RAW'length,
      "A11.2 Raw output count mismatch. exp=" &
      integer'image(C_EXP_RAW'length) &
      " got=" & integer'image(integer(out_idx))
    );
    check(oBufferOverflow = '0', "A11.2 Raw: buffer overflow should not occur");

    if err_count > 0 then
      report "tb_A11_2 RESULT: FAIL (" & integer'image(err_count) & " errors)" severity failure;
    else
      report "tb_A11_2 RESULT: PASS" severity note;
    end if;
    finish;
  end process;
end;
