----------------------------------------------------------------------------------
-- Engineer:    Vitor Mendes Camilo
--
-- Module Name: A20_compute_temp - Behavioral
-- Description: Code segment A.20 — computation of the auxiliary variable TEMP.
--              Q = RItype + 365, so a single context read (Aq, Nq at Q)
--              supplies everything needed:
--                RItype = 0 → TEMP = Aq                   (N unused)
--                RItype = 1 → TEMP = Aq + (Nq >> 1)
--
----------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.openjls_pkg.all;

entity a20_compute_temp is
  generic (
    A_WIDTH : natural := CO_AQ_WIDTH_STD;
    N_WIDTH : natural := CO_NQ_WIDTH_STD
  );
  port (
    iRItype : in    std_logic;
    iAq     : in    unsigned (A_WIDTH - 1 downto 0);
    iNq     : in    unsigned (N_WIDTH - 1 downto 0);
    oTemp   : out   unsigned (A_WIDTH - 1 downto 0)
  );
end entity a20_compute_temp;

architecture behavioral of a20_compute_temp is

begin

  assert A_WIDTH >= N_WIDTH
    report "A_WIDTH has to be >= than N_WIDTH"
    severity failure;

  oTemp <= iAq when iRItype = '0' else
           iAq + resize(shift_right(iNq, 1), A_WIDTH);

end architecture behavioral;
