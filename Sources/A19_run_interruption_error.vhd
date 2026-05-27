----------------------------------------------------------------------------------
  -- Engineer:    Vitor Mendes Camilo
  --
  -- Module Name: A19_run_interruption_error - Behavioral
  -- Description: Code segment A.19 — error computation for run-interruption
  --              sample (lossless only).
  --
  --              With NEAR=0, the T.87 Quantize() step is identity and
  --              Rx = Ix, so no reconstruction is produced here. Only:
  --                - sign flip when RItype=0 and Ra > Rb
  --                - modulo reduction (A.9 inlined)
  ----------------------------------------------------------------------------------
  use work.common.all;

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity a19_run_interruption_error is
  generic (
    BITNESS : natural range 8 to 16 := CO_BITNESS_STD;
    RANGE_P : natural               := CO_RANGE_STD
  );
  port (
    iErrval : in    signed (BITNESS downto 0);
    iRItype : in    std_logic;
    iRa     : in    unsigned (BITNESS - 1 downto 0);
    iRb     : in    unsigned (BITNESS - 1 downto 0);
    oErrval : out   signed (BITNESS downto 0);
    oSign   : out   std_logic
  );
end entity a19_run_interruption_error;

architecture behavioral of a19_run_interruption_error is

begin

  p_ri_error : process (iErrval, iRItype, iRa, iRb) is

    variable vErr    : integer;
    variable vErrAdj : integer;

  begin

    -- Sign adjustment: RItype=0 and Ra > Rb → negate error
    if (iRItype = '0' and iRa > iRb) then
      vErr  := - to_integer(iErrval);
      oSign <= CO_SIGN_NEG;
    else
      vErr  := to_integer(iErrval);
      oSign <= CO_SIGN_POS;
    end if;

    -- Modulo reduction (A.9 inline)
    vErrAdj := vErr;

    if (vErrAdj < 0) then
      vErrAdj := vErrAdj + RANGE_P;
    end if;

    if (vErrAdj >= (RANGE_P + 1) / 2) then
      vErrAdj := vErrAdj - RANGE_P;
    end if;

    oErrval <= to_signed(vErrAdj, oErrval'length);

  end process p_ri_error;

end architecture behavioral;
