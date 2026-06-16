----------------------------------------------------------------------------------
-- Engineer:    Vitor Mendes Camilo
--
-- Module Name: A14_run_length_determination - Behavioral
-- Description: Code segment A.14 — run-length determination (lossless only).
--              With NEAR=0, the T.87 condition  |Ix - RUNval| <= NEAR
--              reduces to  Ix == RUNval  (RUNval = Ra).
--              In lossless mode, Rx = Ix always, so oRx is not produced.
----------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.openjls_pkg.all;

entity a14_run_length_determination is
  generic (
    BITNESS       : natural range 8 to 16 := CO_BITNESS_STD;
    RUN_CNT_WIDTH : natural               := 16
  );
  port (
    iRa           : in    unsigned (BITNESS - 1 downto 0);
    iIx           : in    unsigned (BITNESS - 1 downto 0);
    iRunCnt       : in    unsigned (RUN_CNT_WIDTH - 1 downto 0);
    iEol          : in    std_logic;
    oRunCnt       : out   unsigned (RUN_CNT_WIDTH - 1 downto 0);
    oRunHit       : out   std_logic;
    oRunContinue  : out   std_logic
  );
end entity a14_run_length_determination;

architecture behavioral of a14_run_length_determination is

  signal sRunHit : std_logic;

begin

  sRunHit      <= '1' when iIx = iRa else
                  '0';
  oRunCnt      <= iRunCnt + 1 when sRunHit = '1' else
                  iRunCnt;
  oRunHit      <= sRunHit;
  oRunContinue <= sRunHit and not iEol;

end architecture behavioral;
