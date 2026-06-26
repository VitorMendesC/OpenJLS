----------------------------------------------------------------------------------
-- Engineer:    Vitor Mendes Camilo
--
-- Module Name: gradient_comp - Behavioral
--
-- Description:                         Code segment A.1
--                                      Local gradient computation for context determination
--
----------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.openjls_pkg.all;

entity a1_gradient_comp is
  generic (
    BITNESS : natural range 8 to 16 := CO_BITNESS_STD
  );
  port (
    iA      : in    unsigned (BITNESS - 1 downto 0);
    iB      : in    unsigned (BITNESS - 1 downto 0);
    iC      : in    unsigned (BITNESS - 1 downto 0);
    iD      : in    unsigned (BITNESS - 1 downto 0);
    oD1     : out   signed (BITNESS downto 0);
    oD2     : out   signed (BITNESS downto 0);
    oD3     : out   signed (BITNESS downto 0)
  );
end entity a1_gradient_comp;

architecture behavioral of a1_gradient_comp is

begin

  oD1 <= signed('0' & iD) - signed('0' & iB);
  oD2 <= signed('0' & iB) - signed('0' & iC);
  oD3 <= signed('0' & iC) - signed('0' & iA);

end architecture behavioral;
