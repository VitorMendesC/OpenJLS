----------------------------------------------------------------------------------
-- Engineer:    Vitor Mendes Camilo
--
-- Module Name: quant_gradient_merging - Behavioral
--
-- Description:                       Code segment A.4.1
--                                    Text only, described on section A.3.4
--
----------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.openjls_pkg.all;

entity a4_1_quant_gradient_merging is
  port (
    iQ1   : in    signed(3 downto 0);
    iQ2   : in    signed(3 downto 0);
    iQ3   : in    signed(3 downto 0);
    oQ1   : out   signed(3 downto 0);
    oQ2   : out   signed(3 downto 0);
    oQ3   : out   signed(3 downto 0);
    oSign : out   std_logic
  );
end entity a4_1_quant_gradient_merging;

architecture behavioral of a4_1_quant_gradient_merging is

  signal sSign : std_logic;

begin

  -- Sign of first non-zero (1 if negative)
  sSign <= CO_SIGN_NEG when iQ1 < 0 else
           CO_SIGN_NEG when (iQ1 = 0 and iQ2 < 0) else
           CO_SIGN_NEG when (iQ1 = 0 and iQ2 = 0 and iQ3 < 0) else
           CO_SIGN_POS;

  -- Flip quantized values if sign is negative
  oQ1 <= - iQ1 when sSign = CO_SIGN_NEG else
         iQ1;
  oQ2 <= - iQ2 when sSign = CO_SIGN_NEG else
         iQ2;
  oQ3 <= - iQ3 when sSign = CO_SIGN_NEG else
         iQ3;

  oSign <= sSign;

end architecture behavioral;
