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

use work.Common.all;

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity A20_compute_temp is
  generic (
    A_WIDTH : natural := CO_AQ_WIDTH_STD;
    N_WIDTH : natural := CO_NQ_WIDTH_STD
  );
  port (
    iRItype : in std_logic;
    iAq     : in unsigned (A_WIDTH - 1 downto 0);
    iNq     : in unsigned (N_WIDTH - 1 downto 0);
    oTemp   : out unsigned (A_WIDTH - 1 downto 0)
  );
end A20_compute_temp;

architecture Behavioral of A20_compute_temp is
begin

  oTemp <= iAq when iRItype = '0'
    else
    iAq + resize(shift_right(iNq, 1), A_WIDTH); -- NOTE: Assumes Nq width < Aq width

end Behavioral;
