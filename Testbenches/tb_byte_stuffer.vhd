library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

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

  constant CLK_PERIOD  : time    := 10 ns;
  constant IN_WIDTH    : natural := 8;
  constant OUT_WIDTH   : natural := 8;
  constant BUFFER_WIDTH : natural := 2 * IN_WIDTH + IN_WIDTH / 8; -- 17

  signal iClk       : std_logic := '0';
  signal iRst       : std_logic := '0';
  signal iValid     : std_logic := '0';
  signal iWord      : std_logic_vector(IN_WIDTH  - 1 downto 0) := (others => '0');
  signal oReady     : std_logic;
  signal oWord      : std_logic_vector(OUT_WIDTH - 1 downto 0);
  signal oWordValid : std_logic;
  signal iReady     : std_logic := '1';

  type byte_array_t is array (natural range <>) of std_logic_vector(7 downto 0);

  -- Test 1: no 0xFF bytes — output equals input
  constant C_IN_T1  : byte_array_t := (x"12", x"34", x"56", x"78");
  constant C_EXP_T1 : byte_array_t := (x"12", x"34", x"56", x"78");

  -- Test 2: 0xFF followed by 0x80
  --   Bit stream after stuffing: "11111111" "0" "10000000" = 17 bits
  --   Output 1 (bits 0-7):  "11111111"       = 0xFF
  --   Output 2 (bits 8-15): "0" "1000000"    = 0x40
  constant C_IN_T2  : byte_array_t := (x"FF", x"80");
  constant C_EXP_T2 : byte_array_t := (x"FF", x"40");

  -- Test 3: two consecutive 0xFF bytes followed by 0x00
  --   After 0xFF:            "11111111" "0"                        count=9
  --   Emit 0xFF; leftover:   "0"                                   count=1
  --   After 0xFF:            "0" "11111111" "0"                    count=10
  --   Emit 0x7F; leftover:   "1" "0"                               count=2
  --   After 0x00:            "1" "0" "00000000"                    count=10
  --   Emit 0x80; leftover:   "0" "0"                               count=2
  constant C_IN_T3  : byte_array_t := (x"FF", x"FF", x"00");
  constant C_EXP_T3 : byte_array_t := (x"FF", x"7F", x"80");

begin
  iClk <= not iClk after CLK_PERIOD / 2;

  dut : entity work.byte_stuffer
    generic map(
      IN_WIDTH     => IN_WIDTH,
      OUT_WIDTH    => OUT_WIDTH,
      BUFFER_WIDTH => BUFFER_WIDTH
    )
    port map(
      iClk       => iClk,
      iRst       => iRst,
      iValid     => iValid,
      iWord      => iWord,
      oReady     => oReady,
      oWord      => oWord,
      oWordValid => oWordValid,
      iReady     => iReady
    );

  stim : process
    variable out_idx : natural := 0;
  begin

    -- Reset
    iRst   <= '1';
    iValid <= '0';
    iReady <= '1';
    wait until rising_edge(iClk);
    wait until rising_edge(iClk);
    iRst <= '0';

    ----------------------------------------------------------------------------
    -- Test 1: no 0xFF — output equals input
    ----------------------------------------------------------------------------
    out_idx := 0;
    for i in C_IN_T1'range loop
      iValid <= '1';
      iWord  <= C_IN_T1(i);
      wait until rising_edge(iClk);
      wait for 1 ns;
      check(oReady = '1', "T1: oReady deasserted unexpectedly");
      if oWordValid = '1' then
        check(out_idx < C_EXP_T1'length,
          "T1: unexpected extra output at index " & integer'image(out_idx));
        check(oWord = C_EXP_T1(out_idx),
          "T1: mismatch at index " & integer'image(out_idx) &
          " exp=0x" & integer'image(to_integer(unsigned(C_EXP_T1(out_idx)))) &
          " got=0x" & integer'image(to_integer(unsigned(oWord))));
        out_idx := out_idx + 1;
      end if;
    end loop;
    iValid <= '0';
    wait until rising_edge(iClk);
    wait for 1 ns;
    check(out_idx = C_EXP_T1'length,
      "T1: output count mismatch. exp=" & integer'image(C_EXP_T1'length) &
      " got=" & integer'image(out_idx));

    ----------------------------------------------------------------------------
    -- Test 2: single 0xFF — stuffed '0' bit shifts following byte right by 1
    ----------------------------------------------------------------------------
    iRst   <= '1';
    iValid <= '0';
    wait until rising_edge(iClk);
    wait until rising_edge(iClk);
    iRst <= '0';

    out_idx := 0;
    for i in C_IN_T2'range loop
      iValid <= '1';
      iWord  <= C_IN_T2(i);
      wait until rising_edge(iClk);
      wait for 1 ns;
      check(oReady = '1', "T2: oReady deasserted unexpectedly");
      if oWordValid = '1' then
        check(out_idx < C_EXP_T2'length,
          "T2: unexpected extra output at index " & integer'image(out_idx));
        check(oWord = C_EXP_T2(out_idx),
          "T2: mismatch at index " & integer'image(out_idx) &
          " exp=0x" & integer'image(to_integer(unsigned(C_EXP_T2(out_idx)))) &
          " got=0x" & integer'image(to_integer(unsigned(oWord))));
        out_idx := out_idx + 1;
      end if;
    end loop;
    iValid <= '0';
    wait until rising_edge(iClk);
    wait for 1 ns;
    check(out_idx = C_EXP_T2'length,
      "T2: output count mismatch. exp=" & integer'image(C_EXP_T2'length) &
      " got=" & integer'image(out_idx));

    ----------------------------------------------------------------------------
    -- Test 3: two consecutive 0xFF — each stuffed independently
    ----------------------------------------------------------------------------
    iRst   <= '1';
    iValid <= '0';
    wait until rising_edge(iClk);
    wait until rising_edge(iClk);
    iRst <= '0';

    out_idx := 0;
    for i in C_IN_T3'range loop
      iValid <= '1';
      iWord  <= C_IN_T3(i);
      wait until rising_edge(iClk);
      wait for 1 ns;
      check(oReady = '1', "T3: oReady deasserted unexpectedly");
      if oWordValid = '1' then
        check(out_idx < C_EXP_T3'length,
          "T3: unexpected extra output at index " & integer'image(out_idx));
        check(oWord = C_EXP_T3(out_idx),
          "T3: mismatch at index " & integer'image(out_idx) &
          " exp=0x" & integer'image(to_integer(unsigned(C_EXP_T3(out_idx)))) &
          " got=0x" & integer'image(to_integer(unsigned(oWord))));
        out_idx := out_idx + 1;
      end if;
    end loop;
    iValid <= '0';
    wait until rising_edge(iClk);
    wait for 1 ns;
    check(out_idx = C_EXP_T3'length,
      "T3: output count mismatch. exp=" & integer'image(C_EXP_T3'length) &
      " got=" & integer'image(out_idx));

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
