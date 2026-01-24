
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use Work.Common.all;

entity tb_A4 is
end;

architecture bench of tb_A4 is
  constant cStdWait : time := 20 ns;

  -- Generics
  constant BITNESS : natural range 8 to 16 := 12;

  -- Derived constants per T87 A.4
  constant NEAR0    : integer := 0;
  constant NEAR3    : integer := 3;
  constant MAX_VAL  : integer := 2 ** BITNESS - 1;
  constant MIN_VAL  : integer := - (2 ** BITNESS);
  constant BASIC_T1 : integer := 3;
  constant BASIC_T2 : integer := 7;
  constant BASIC_T3 : integer := 21;

  -- Functions
  function clamp (
    i        : integer;
    j        : integer;
    MaxValue : integer) return integer is
  begin
    if i > MaxValue or i < j then
      return j;
    else
      return i;
    end if;
  end function;

  constant FACTOR : integer := (minimum(MAX_VAL, 4095) + 128) / 256;

  function t1_for(near : integer) return integer is
  begin
    return clamp(FACTOR * (BASIC_T1 - 2) + 2 + 3 * near, near + 1, MAX_VAL);
  end function;

  function t2_for(near : integer) return integer is
    variable t1v         : integer := t1_for(near);
  begin
    return clamp(FACTOR * (BASIC_T2 - 3) + 3 + 5 * near, t1v, MAX_VAL);
  end function;

  function t3_for(near : integer) return integer is
    variable t2v         : integer := t2_for(near);
  begin
    return clamp(FACTOR * (BASIC_T3 - 4) + 4 + 7 * near, t2v, MAX_VAL);
  end function;

  -- Constants
  constant T1_0 : integer := t1_for(NEAR0);
  constant T2_0 : integer := t2_for(NEAR0);
  constant T3_0 : integer := t3_for(NEAR0);

  constant T1_3 : integer := t1_for(NEAR3);
  constant T2_3 : integer := t2_for(NEAR3);
  constant T3_3 : integer := t3_for(NEAR3);

  -- Ports
  signal iD1    : signed (BITNESS downto 0) := (others => '0');
  signal iD2    : signed (BITNESS downto 0) := (others => '0');
  signal iD3    : signed (BITNESS downto 0) := (others => '0');
  signal oQ1_n0 : signed (3 downto 0);
  signal oQ2_n0 : signed (3 downto 0);
  signal oQ3_n0 : signed (3 downto 0);
  signal oQ1_n3 : signed (3 downto 0);
  signal oQ2_n3 : signed (3 downto 0);
  signal oQ3_n3 : signed (3 downto 0);

  -- Test vectors
  type test_vec_t is record
    di  : integer;
    exp : integer;
  end record;

  type test_vec_array_t is array (natural range <>) of test_vec_t;

  -- Expected value tables
  constant test_vectors_n0 : test_vec_array_t := (
  (di => MIN_VAL, exp => - 4),
  (di => - T3_0 - 1, exp => - 4),
  (di => - T3_0, exp => - 4),
  (di => - T3_0 + 1, exp => - 3),
  (di => - T2_0 - 1, exp => - 3),
  (di => - T2_0, exp => - 3),
  (di => - T2_0 + 1, exp => - 2),
  (di => - T1_0 - 1, exp => - 2),
  (di => - T1_0, exp => - 2),
  (di => - T1_0 + 1, exp => - 1),
  (di => - NEAR0 - 1, exp => - 1),
  (di => - NEAR0, exp => 0),
  (di => 0, exp => 0),
  (di => NEAR0, exp => 0),
  (di => NEAR0 + 1, exp => 1),
  (di => T1_0 - 1, exp => 1),
  (di => T1_0, exp => 2),
  (di => T2_0 - 1, exp => 2),
  (di => T2_0, exp => 3),
  (di => T3_0 - 1, exp => 3),
  (di => T3_0, exp => 4),
  (di => MAX_VAL, exp => 4)
  );

  constant test_vectors_n3 : test_vec_array_t := (
  (di => MIN_VAL, exp => - 4),
  (di => - T3_3 - 1, exp => - 4),
  (di => - T3_3, exp => - 4),
  (di => - T3_3 + 1, exp => - 3),
  (di => - T2_3 - 1, exp => - 3),
  (di => - T2_3, exp => - 3),
  (di => - T2_3 + 1, exp => - 2),
  (di => - T1_3 - 1, exp => - 2),
  (di => - T1_3, exp => - 2),
  (di => - T1_3 + 1, exp => - 1),
  (di => - NEAR3 - 1, exp => - 1),
  (di => - NEAR3, exp => 0),
  (di => 0, exp => 0),
  (di => NEAR3, exp => 0),
  (di => NEAR3 + 1, exp => 1),
  (di => T1_3 - 1, exp => 1),
  (di => T1_3, exp => 2),
  (di => T2_3 - 1, exp => 2),
  (di => T2_3, exp => 3),
  (di => T3_3 - 1, exp => 3),
  (di => T3_3, exp => 4),
  (di => MAX_VAL, exp => 4)
  );
begin

  A4_quantization_gradients_inst_n0 : entity work.A4_quantization_gradients
    generic map(
      BITNESS => BITNESS,
      NEAR    => NEAR0
    )
    port map
    (
      iD1 => iD1,
      iD2 => iD2,
      iD3 => iD3,
      oQ1 => oQ1_n0,
      oQ2 => oQ2_n0,
      oQ3 => oQ3_n0
    );

  A4_quantization_gradients_inst_n3 : entity work.A4_quantization_gradients
    generic map(
      BITNESS => BITNESS,
      NEAR    => NEAR3
    )
    port map
    (
      iD1 => iD1,
      iD2 => iD2,
      iD3 => iD3,
      oQ1 => oQ1_n3,
      oQ2 => oQ2_n3,
      oQ3 => oQ3_n3
    );

  stimulus : process
    variable di  : integer;
    variable exp : integer;
  begin
    for idx in test_vectors_n0'range loop
      di  := test_vectors_n0(idx).di;
      exp := test_vectors_n0(idx).exp;

      iD1 <= to_signed(di, iD1'length);
      iD2 <= to_signed(di, iD2'length);
      iD3 <= to_signed(di, iD3'length);
      wait for cStdWait;

      assert oQ1_n0 = to_signed(exp, oQ1_n0'length)
      report "oQ1 NEAR=0 mismatch Di=" & integer'image(di) &
        " exp=" & integer'image(exp) &
        " got=" & integer'image(to_integer(oQ1_n0))
        severity error;
      assert oQ2_n0 = to_signed(exp, oQ2_n0'length)
      report "oQ2 NEAR=0 mismatch Di=" & integer'image(di) &
        " exp=" & integer'image(exp) &
        " got=" & integer'image(to_integer(oQ2_n0))
        severity error;
      assert oQ3_n0 = to_signed(exp, oQ3_n0'length)
      report "oQ3 NEAR=0 mismatch Di=" & integer'image(di) &
        " exp=" & integer'image(exp) &
        " got=" & integer'image(to_integer(oQ3_n0))
        severity error;
    end loop;

    for idx in test_vectors_n3'range loop
      di  := test_vectors_n3(idx).di;
      exp := test_vectors_n3(idx).exp;

      iD1 <= to_signed(di, iD1'length);
      iD2 <= to_signed(di, iD2'length);
      iD3 <= to_signed(di, iD3'length);
      wait for cStdWait;

      assert oQ1_n3 = to_signed(exp, oQ1_n3'length)
      report "oQ1 NEAR=3 mismatch Di=" & integer'image(di) &
        " exp=" & integer'image(exp) &
        " got=" & integer'image(to_integer(oQ1_n3))
        severity error;
      assert oQ2_n3 = to_signed(exp, oQ2_n3'length)
      report "oQ2 NEAR=3 mismatch Di=" & integer'image(di) &
        " exp=" & integer'image(exp) &
        " got=" & integer'image(to_integer(oQ2_n3))
        severity error;
      assert oQ3_n3 = to_signed(exp, oQ3_n3'length)
      report "oQ3 NEAR=3 mismatch Di=" & integer'image(di) &
        " exp=" & integer'image(exp) &
        " got=" & integer'image(to_integer(oQ3_n3))
        severity error;
    end loop;

    report "tb_A4 complete" severity note;
    wait;
  end process;

end;
