
library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use std.env.all;
  use work.common.all;

entity tb_a4 is
end entity tb_a4;

architecture bench of tb_a4 is

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

  constant CSTDWAIT        : time := 20 ns;

  -- Generics
  constant BITNESS         : natural range 8 to 16 := 12;

  -- Derived constants per T87 A.4
  constant MAX_VAL         : integer := 2 ** BITNESS - 1;
  constant MIN_VAL         : integer := - (2 ** BITNESS);
  constant BASIC_T1        : integer := 3;
  constant BASIC_T2        : integer := 7;
  constant BASIC_T3        : integer := 21;

  -- Functions

  function clamp (
    i        : integer;
    j        : integer;
    maxvalue : integer
  ) return integer is
  begin

    if (i > maxvalue or i < j) then
      return j;
    else
      return i;
    end if;

  end function clamp;

  constant FACTOR          : integer := (math_min(MAX_VAL, 4095) + 128) / 256;
  constant T1              : integer := clamp(FACTOR * (BASIC_T1 - 2) + 2, 1, MAX_VAL);
  constant T2              : integer := clamp(FACTOR * (BASIC_T2 - 3) + 3, T1, MAX_VAL);
  constant T3              : integer := clamp(FACTOR * (BASIC_T3 - 4) + 4, T2, MAX_VAL);

  -- Ports
  signal iD1               : signed (BITNESS downto 0);
  signal iD2               : signed (BITNESS downto 0);
  signal iD3               : signed (BITNESS downto 0);
  signal oQ1               : signed (3 downto 0);
  signal oQ2               : signed (3 downto 0);
  signal oQ3               : signed (3 downto 0);

  -- Test vectors

  type test_vec_t is record
    di  : integer;
    exp : integer;
  end record test_vec_t;

  type test_vec_array_t is array (natural range <>) of test_vec_t;

  constant TEST_VECTORS    : test_vec_array_t :=
  (
    (
      di  => MIN_VAL,
      exp => - 4
    ),
    (
      di  => - T3 - 1,
      exp => - 4
    ),
    (
      di  => - T3,
      exp => - 4
    ),
    (
      di  => - T3 + 1,
      exp => - 3
    ),
    (
      di  => - T2 - 1,
      exp => - 3
    ),
    (
      di  => - T2,
      exp => - 3
    ),
    (
      di  => - T2 + 1,
      exp => - 2
    ),
    (
      di  => - T1 - 1,
      exp => - 2
    ),
    (
      di  => - T1,
      exp => - 2
    ),
    (
      di  => - T1 + 1,
      exp => - 1
    ),
    (
      di  => - 1,
      exp => - 1
    ),
    (
      di  => 0,
      exp => 0
    ),
    (
      di  => 1,
      exp => 1
    ),
    (
      di  => T1 - 1,
      exp => 1
    ),
    (
      di  => T1,
      exp => 2
    ),
    (
      di  => T2 - 1,
      exp => 2
    ),
    (
      di  => T2,
      exp => 3
    ),
    (
      di  => T3 - 1,
      exp => 3
    ),
    (
      di  => T3,
      exp => 4
    ),
    (
      di  => MAX_VAL,
      exp => 4
    )
  );

begin

  dut : entity work.a4_quantization_gradients(behavioral)

    generic map (
      BITNESS => BITNESS
    )
    port map (
      iD1     => iD1,
      iD2     => iD2,
      iD3     => iD3,
      oQ1     => oQ1,
      oQ2     => oQ2,
      oQ3     => oQ3
    );

  stimulus : process is

    variable di  : integer;
    variable exp : integer;

  begin

    -- Initial values (no defaults — set explicitly here)
    iD1 <= (others => '0');
    iD2 <= (others => '0');
    iD3 <= (others => '0');

    for idx in TEST_VECTORS'range loop

      di  := test_vectors(idx).di;
      exp := test_vectors(idx).exp;

      iD1 <= to_signed(di, iD1'length);
      iD2 <= to_signed(di, iD2'length);
      iD3 <= to_signed(di, iD3'length);
      wait for CSTDWAIT;

      check(oQ1 = to_signed(exp, oQ1'length),
            "oQ1 mismatch Di=" & integer'image(di) &
            " exp=" & integer'image(exp) &
            " got=" & integer'image(to_integer(oQ1))
          );
      check(oQ2 = to_signed(exp, oQ2'length),
            "oQ2 mismatch Di=" & integer'image(di) &
            " exp=" & integer'image(exp) &
            " got=" & integer'image(to_integer(oQ2))
          );
      check(oQ3 = to_signed(exp, oQ3'length),
            "oQ3 mismatch Di=" & integer'image(di) &
            " exp=" & integer'image(exp) &
            " got=" & integer'image(to_integer(oQ3))
          );

    end loop;

    if (errCount > 0) then
      report "tb_A4 RESULT: FAIL (" & integer'image(errCount) & " errors)"
        severity failure;
    else
      report "tb_A4 RESULT: PASS"
        severity note;
    end if;

    finish;

  end process stimulus;

end architecture bench;
