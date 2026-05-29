library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.common.all;

library osvvm;
  context osvvm.OsvvmContext;

library tb_support;
  use tb_support.tb_support_pkg.all;

entity tb_a8_osvvm is
end entity tb_a8_osvvm;

architecture sim of tb_a8_osvvm is

  constant BITNESS : natural := CO_BITNESS_STD;
  constant MAX_VAL : natural := CO_MAX_VAL_STD;

  constant ERR_MIN : integer := -(2 ** BITNESS);
  constant ERR_MAX : integer :=  (2 ** BITNESS) - 1;

  signal sErrorVal : signed(BITNESS downto 0)       := (others => '0');
  signal sPx       : unsigned(BITNESS - 1 downto 0) := (others => '0');
  signal sSign     : std_logic                      := CO_SIGN_POS;
  signal sRx       : unsigned(BITNESS - 1 downto 0);

  function ref_rx (
    px        : integer;
    err       : integer;
    sign_bit  : std_logic;
    max_val_g : integer
  ) return integer is
    variable v : integer;
  begin
    if sign_bit = CO_SIGN_POS then
      v := px + err;
    else
      v := px - err;
    end if;
    if v < 0 then
      v := 0;
    elsif v > max_val_g then
      v := max_val_g;
    end if;
    return v;
  end function;

begin

  dut : entity work.a8_error_quantization
    generic map (
      BITNESS => BITNESS,
      MAX_VAL => MAX_VAL
    )
    port map (
      iErrorVal => sErrorVal,
      iPx       => sPx,
      iSign     => sSign,
      oRx       => sRx
    );

  stim : process is
    variable rv          : RandomPType;
    variable cov         : CovPType;
    variable px_v        : integer;
    variable err_v       : integer;
    variable sign_v      : std_logic;
    variable expected    : integer;
    variable actual      : integer;
    variable regime      : integer;
    variable sign_idx    : integer;
    constant N_RAND      : natural := 5000;
  begin
    SetAlertLogName("tb_a8_osvvm");
    SetLogEnable(PASSED, FALSE);

    rv.InitSeed(rv'instance_name);

    -- Cover the three output regimes (clamped low, in-range, clamped high)
    -- crossed with sign. This catches the boundary bugs that uniform random
    -- would only hit by accident.
    cov.AddCross(
      "Rx regime x Sign",
      GenBin(ATLEAST => 50, Min => 0, Max => 2, NumBin => 3),   -- 0=low clamp, 1=mid, 2=high clamp
      GenBin(ATLEAST => 50, Min => 0, Max => 1, NumBin => 2)    -- 0=pos, 1=neg
    );

    -- Directed corners first (locked-in regressions)
    for s in 0 to 1 loop
      if s = 0 then
        sign_v := CO_SIGN_POS;
      else
        sign_v := CO_SIGN_NEG;
      end if;
      for corner in 0 to 5 loop
        case corner is
          when 0 => px_v := 0;       err_v := 0;
          when 1 => px_v := MAX_VAL; err_v := 0;
          when 2 => px_v := 0;       err_v := ERR_MIN;
          when 3 => px_v := MAX_VAL; err_v := ERR_MAX;
          when 4 => px_v := MAX_VAL / 2; err_v := 1;
          when 5 => px_v := MAX_VAL / 2; err_v := -1;
        end case;

        sPx       <= to_unsigned(px_v, sPx'length);
        sErrorVal <= to_signed(err_v, sErrorVal'length);
        sSign     <= sign_v;
        wait for 1 ns;

        expected := ref_rx(px_v, err_v, sign_v, MAX_VAL);
        actual   := to_integer(sRx);
        AffirmIfEqual(actual, expected,
          "directed corner " & integer'image(corner) & " sign=" & std_logic'image(sign_v));
      end loop;
    end loop;

    -- Random sweep with coverage feedback
    for i in 1 to N_RAND loop
      px_v  := rv.RandInt(0, MAX_VAL);
      err_v := rv.RandInt(ERR_MIN, ERR_MAX);
      if rv.RandInt(0, 1) = 0 then
        sign_v := CO_SIGN_POS;
      else
        sign_v := CO_SIGN_NEG;
      end if;

      sPx       <= to_unsigned(px_v, sPx'length);
      sErrorVal <= to_signed(err_v, sErrorVal'length);
      sSign     <= sign_v;
      wait for 1 ns;

      expected := ref_rx(px_v, err_v, sign_v, MAX_VAL);
      actual   := to_integer(sRx);
      AffirmIfEqual(actual, expected,
        "random px=" & integer'image(px_v) &
        " err=" & integer'image(err_v) &
        " sign=" & std_logic'image(sign_v));

      if expected = 0 then
        regime := 0;
      elsif expected = MAX_VAL then
        regime := 2;
      else
        regime := 1;
      end if;
      if sign_v = CO_SIGN_POS then
        sign_idx := 0;
      else
        sign_idx := 1;
      end if;
      cov.ICover((regime, sign_idx));

      exit when cov.IsCovered and i > 200;
    end loop;

    cov.WriteBin;
    AffirmIf(cov.IsCovered, "Coverage closed");

    end_of_test("tb_a8_osvvm");
    wait;
  end process;

end architecture sim;
