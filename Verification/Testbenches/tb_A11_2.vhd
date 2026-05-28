use work.common.all;

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use std.env.all;

library openlogic_base;
  use openlogic_base.olo_base_pkg_math.log2ceil;

entity tb_a11_2 is
end entity tb_a11_2;

architecture bench of tb_a11_2 is

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

  constant CLK_PERIOD      : time    := 10 ns;
  constant LIMIT           : natural := CO_LIMIT_STD;
  constant UNARY_WIDTH     : natural := CO_UNARY_WIDTH_STD;
  constant SUFFIX_WIDTH    : natural := CO_SUFFIX_WIDTH_STD;
  constant SUFFIXLEN_WIDTH : natural := CO_SUFFIXLEN_WIDTH_STD;
  constant OUT_WIDTH       : natural := CO_LIMIT_STD;

  signal iClk              : std_logic;
  signal iRst              : std_logic;
  signal iStall            : std_logic;

  signal iRawValid         : std_logic;
  signal iRawLen           : unsigned(SUFFIXLEN_WIDTH - 1 downto 0);
  signal iRawVal           : unsigned(SUFFIX_WIDTH - 1 downto 0);

  signal iGolombValid      : std_logic;
  signal iUnaryZeros       : unsigned(UNARY_WIDTH - 1 downto 0);
  signal iSuffixLen        : unsigned(SUFFIXLEN_WIDTH - 1 downto 0);
  signal iSuffixVal        : unsigned(SUFFIX_WIDTH - 1 downto 0);

  signal oWord             : std_logic_vector(OUT_WIDTH - 1 downto 0);
  signal oWordValid        : std_logic;
  signal oValidLen         : unsigned(log2ceil(OUT_WIDTH + 1) - 1 downto 0);

  -- Return the top 'nbits' bits of word as an unsigned vector
  function top_bits (
    word  : std_logic_vector;
    nbits : natural
  ) return unsigned is
  begin

    return unsigned(word(word'high downto word'high - nbits + 1));

  end function top_bits;

begin

  clk_proc : process is
  begin

    iClk <= '0';
    wait for CLK_PERIOD / 2;
    iClk <= '1';
    wait for CLK_PERIOD / 2;

  end process clk_proc;

  dut : entity work.a11_2_bit_packer(behavioral)

    generic map (
      LIMIT           => LIMIT,
      UNARY_WIDTH     => UNARY_WIDTH,
      SUFFIX_WIDTH    => SUFFIX_WIDTH,
      SUFFIXLEN_WIDTH => SUFFIXLEN_WIDTH,
      OUT_WIDTH       => OUT_WIDTH
    )
    port map (
      iClk            => iClk,
      iRst            => iRst,
      iStall          => iStall,
      iRawValid       => iRawValid,
      iRawLen         => iRawLen,
      iRawVal         => iRawVal,
      iGolombValid    => iGolombValid,
      iUnaryZeros     => iUnaryZeros,
      iSuffixLen      => iSuffixLen,
      iSuffixVal      => iSuffixVal,
      oWord           => oWord,
      oWordValid      => oWordValid,
      oValidLen       => oValidLen
    );

  stim : process is

    -- Drive one Golomb symbol and check the registered output one cycle later.
    -- Expected output: unaryZeros zeros + '1' marker + suffix bits, MSB-aligned.
    -- oValidLen = unaryZeros + 1 + suffixLen.
    -- Drive one Golomb symbol and check the registered output in the same cycle
    -- (1 ns after the rising edge that captured the inputs).
    procedure send_golomb (
      unary_v  : natural;
      suf_len  : natural;
      suf_val  : natural;
      exp_bits : natural;
      exp_len  : natural;
      tag      : string
    ) is
    begin

      iGolombValid <= '1';
      iUnaryZeros  <= to_unsigned(unary_v, iUnaryZeros'length);
      iSuffixLen   <= to_unsigned(suf_len,  iSuffixLen'length);
      iSuffixVal   <= to_unsigned(suf_val,  iSuffixVal'length);
      wait until rising_edge(iClk);
      wait for 1 ns;                                                                       -- outputs settled after capture edge

      check(oWordValid = '1', tag & ": oWordValid not asserted");
      check(to_integer(oValidLen) = exp_len,
            tag & ": oValidLen mismatch exp=" & integer'image(exp_len) &
            " got=" & integer'image(to_integer(oValidLen)));
      check(to_integer(top_bits(oWord, exp_len)) = exp_bits,
            tag & ": top bits mismatch exp=" & integer'image(exp_bits) &
            " got=" & integer'image(to_integer(top_bits(oWord, exp_len))));

      iGolombValid <= '0';
      iUnaryZeros  <= (others => '0');
      iSuffixLen   <= (others => '0');
      iSuffixVal   <= (others => '0');

    end procedure send_golomb;

    -- Drive one raw symbol and check the registered output in the same capture cycle.
    procedure send_raw (
      len_v    : natural;
      val_v    : natural;
      exp_bits : natural;
      tag      : string
    ) is
    begin

      iRawValid <= '1';
      iRawLen   <= to_unsigned(len_v, iRawLen'length);
      iRawVal   <= to_unsigned(val_v, iRawVal'length);
      wait until rising_edge(iClk);
      wait for 1 ns;

      check(oWordValid = '1', tag & ": oWordValid not asserted");
      check(to_integer(oValidLen) = len_v,
            tag & ": oValidLen mismatch exp=" & integer'image(len_v) &
            " got=" & integer'image(to_integer(oValidLen)));
      check(to_integer(top_bits(oWord, len_v)) = exp_bits,
            tag & ": top bits mismatch exp=" & integer'image(exp_bits) &
            " got=" & integer'image(to_integer(top_bits(oWord, len_v))));

      iRawValid <= '0';
      iRawLen   <= (others => '0');
      iRawVal   <= (others => '0');

    end procedure send_raw;

    -- Reset DUT
    procedure do_reset is
    begin

      iRst         <= '1';
      iStall       <= '0';
      iRawValid    <= '0';
      iRawLen      <= (others => '0');
      iRawVal      <= (others => '0');
      iGolombValid <= '0';
      iUnaryZeros  <= (others => '0');
      iSuffixLen   <= (others => '0');
      iSuffixVal   <= (others => '0');
      wait until rising_edge(iClk);
      iRst         <= '0';

    end procedure do_reset;

  begin

    -- Initial values (no defaults — set explicitly here)
    iRst         <= '1';
    iStall       <= '0';
    iRawValid    <= '0';
    iRawLen      <= (others => '0');
    iRawVal      <= (others => '0');
    iGolombValid <= '0';
    iUnaryZeros  <= (others => '0');
    iSuffixLen   <= (others => '0');
    iSuffixVal   <= (others => '0');

    -- -----------------------------------------------------------------------
    -- T1: Golomb-only symbols.
    --   Each symbol: unaryZeros + '1' + suffix, MSB-aligned.
    --   Sym 0: unary=3, sufLen=4, sufVal=10 -> "000" + "1" + "1010" = 0x1A (8 bits)
    --   Sym 1: unary=0, sufLen=7, sufVal=85 -> "1" + "1010101"       = 0xD5 (8 bits)
    --   Sym 2: unary=2, sufLen=2, sufVal=1  -> "00" + "1" + "01"     = 0x05 = "00101" (5 bits)
    --   Sym 3: unary=0, sufLen=2, sufVal=2  -> "1" + "10"            = 0x06 = "110" (3 bits)
    --   Sym 4: unary=1, sufLen=1, sufVal=1  -> "0" + "1" + "1"       = 0x03 = "011" (3 bits)
    --   Sym 5: unary=0, sufLen=4, sufVal=9  -> "1" + "1001"          = 0x19 = "11001" (5 bits)
    -- -----------------------------------------------------------------------
    do_reset;
    send_golomb(3, 4, 10, 16#1A#, 8,  "T1-sym0");
    send_golomb(0, 7, 85, 16#D5#, 8,  "T1-sym1");
    send_golomb(2, 2,  1, 16#05#, 5,  "T1-sym2");
    send_golomb(0, 2,  2, 16#06#, 3,  "T1-sym3");
    send_golomb(1, 1,  1, 16#03#, 3,  "T1-sym4");
    send_golomb(0, 4,  9, 16#19#, 5,  "T1-sym5");

    -- -----------------------------------------------------------------------
    -- T2: Raw-only symbols (MSB end, no marker/suffix structure).
    --   Raw 0: len=4, val=5  = "0101" -> top 4 bits = 5
    --   Raw 1: len=4, val=11 = "1011" -> top 4 bits = 11
    --   Raw 2: len=3, val=2  = "010"  -> top 3 bits = 2
    --   Raw 3: len=5, val=25 = "11001"-> top 5 bits = 25
    -- -----------------------------------------------------------------------
    do_reset;
    send_raw(4,  5,  5,  "T2-raw0");
    send_raw(4, 11, 11,  "T2-raw1");
    send_raw(3,  2,  2,  "T2-raw2");
    send_raw(5, 25, 25,  "T2-raw3");

    -- -----------------------------------------------------------------------
    -- T3: Simultaneous raw + Golomb (Run Interruption mode).
    --   Raw: len=3, val=1 -> "001" (3 bits)
    --   Golomb: unary=1, sufLen=3, sufVal=5 -> "0" + "1" + "101" = "01101" (5 bits)
    --   Combined: "001" ++ "01101" = "00101101" (8 bits) = 0x2D
    -- -----------------------------------------------------------------------
    do_reset;
    iRawValid    <= '1';
    iRawLen      <= to_unsigned(3, iRawLen'length);
    iRawVal      <= to_unsigned(1, iRawVal'length);
    iGolombValid <= '1';
    iUnaryZeros  <= to_unsigned(1, iUnaryZeros'length);
    iSuffixLen   <= to_unsigned(3, iSuffixLen'length);
    iSuffixVal   <= to_unsigned(5, iSuffixVal'length);
    wait until rising_edge(iClk);
    wait for 1 ns;

    check(oWordValid = '1', "T3: oWordValid not asserted");
    check(to_integer(oValidLen) = 8, "T3: oValidLen mismatch exp=8 got=" & integer'image(to_integer(oValidLen)));
    check(to_integer(top_bits(oWord, 8)) = 16#2D#,
          "T3: combined bits mismatch exp=0x2D got=" &
          integer'image(to_integer(top_bits(oWord, 8))));

    -- -----------------------------------------------------------------------
    -- T4: Stall — output register frozen while iStall='1'.
    --   Drive a golomb symbol while stalled: register should not capture it.
    --   After stall release, the symbol fires on the next active edge.
    --   Symbol: unary=0, sufLen=3, sufVal=5 -> "1"+"101" = "1101" (4 bits) = 0xD
    -- -----------------------------------------------------------------------
    do_reset;

    -- Assert stall, then drive input
    iStall       <= '1';
    iGolombValid <= '1';
    iUnaryZeros  <= to_unsigned(0, iUnaryZeros'length);
    iSuffixLen   <= to_unsigned(3, iSuffixLen'length);
    iSuffixVal   <= to_unsigned(5, iSuffixVal'length);
    wait until rising_edge(iClk);
    wait for 1 ns;
    -- Stall prevents capture: output should stay at reset value (oWordValid='0')
    check(oWordValid = '0', "T4: oWordValid should stay 0 while stalled");

    -- Release stall — same inputs still driven
    iStall       <= '0';
    wait until rising_edge(iClk);
    wait for 1 ns;
    check(oWordValid = '1', "T4: oWordValid should assert after stall release");
    check(to_integer(oValidLen) = 4, "T4: oValidLen mismatch exp=4 got=" & integer'image(to_integer(oValidLen)));
    check(to_integer(top_bits(oWord, 4)) = 16#D#,
          "T4: bits mismatch exp=0xD got=" & integer'image(to_integer(top_bits(oWord, 4))));
    iGolombValid <= '0';

    -- -----------------------------------------------------------------------
    -- T5: Idle cycle — no valid inputs should produce oWordValid='0'.
    -- -----------------------------------------------------------------------
    do_reset;
    wait until rising_edge(iClk);
    wait until rising_edge(iClk);
    wait for 1 ns;
    check(oWordValid = '0', "T5: oWordValid should be 0 when no symbol presented");

    if (errCount > 0) then
      report "tb_A11_2 RESULT: FAIL (" & integer'image(errCount) & " errors)"
        severity failure;
    else
      report "tb_A11_2 RESULT: PASS"
        severity note;
    end if;

    wait for CLK_PERIOD * 2;
    finish;

  end process stim;

end architecture bench;
