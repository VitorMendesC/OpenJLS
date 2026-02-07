library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_A11_2 is
end;

architecture bench of tb_A11_2 is
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
        assert out_idx < C_EXP_WORDS'length
          report "A11.2 produced unexpected extra output word: " &
                 integer'image(integer(out_idx))
          severity failure;

        assert oWord = C_EXP_WORDS(out_idx)
          report "A11.2 output mismatch at index " &
                 integer'image(integer(out_idx)) &
                 " exp=" & integer'image(to_integer(unsigned(C_EXP_WORDS(out_idx)))) &
                 " got=" & integer'image(to_integer(unsigned(oWord)))
          severity failure;

        out_idx := out_idx + 1;
      end if;
    end loop;

    assert out_idx = C_EXP_WORDS'length
      report "A11.2 output count mismatch. exp=" &
             integer'image(C_EXP_WORDS'length) &
             " got=" & integer'image(integer(out_idx))
      severity failure;

    assert oBufferOverflow = '0'
      report "A11.2 buffer overflow should not occur in directed sequence"
      severity failure;

    report "tb_A11_2 completed" severity note;
    wait;
  end process;
end;
