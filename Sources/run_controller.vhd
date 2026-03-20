----------------------------------------------------------------------------------
-- Engineer:    Vitor Mendes Camilo
--
-- Module Name: run_controller - Behavioral
-- Description: Run controller — one pixel per cycle, no wait states.
--              Handles A14/A15/A16 and injects tokens to the pipeline.
--              Connect iRawMode='1' on the bit packer at instantiation.
--              See Docs/top_level_design.md for pipeline architecture context.
----------------------------------------------------------------------------------
use work.Common.all;

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

entity run_controller is
  generic (
    BITNESS        : natural := CO_BITNESS_STD;
    NEAR           : natural := CO_NEAR_STD;
    IMG_WIDTH_BITS : natural := 16
  );
  port (
    iClk : in std_logic;
    iRst : in std_logic;
    iEOI : in std_logic; -- end of image: resets run state for next scan

    iValid        : in std_logic;
    iIx           : in unsigned(BITNESS - 1 downto 0);
    iRa           : in unsigned(BITNESS - 1 downto 0);
    iRb           : in unsigned(BITNESS - 1 downto 0);
    iRc           : in unsigned(BITNESS - 1 downto 0);
    iModeIsRun    : in std_logic; -- D1=D2=D3=0, registered from A2/A3
    iRunContinues : in std_logic; -- |Ix - RUNval| <= NEAR, registered from pre-stage
    iEOLine       : in std_logic;

    oBpValid     : out std_logic;
    oBpSuffixLen : out unsigned(CO_SUFFIXLEN_WIDTH_STD - 1 downto 0);
    oBpSuffixVal : out unsigned(CO_SUFFIX_WIDTH_STD - 1 downto 0);

    oTokenValid : out std_logic;
    oTokenIsRI  : out std_logic; -- '1' = run-interruption, '0' = regular
    oTokenIx    : out unsigned(BITNESS - 1 downto 0);
    oTokenRa    : out unsigned(BITNESS - 1 downto 0);
    oTokenRb    : out unsigned(BITNESS - 1 downto 0);
    oTokenRc    : out unsigned(BITNESS - 1 downto 0);

    oRUNval : out unsigned(BITNESS - 1 downto 0) -- feeds pre-stage comparator
  );
end run_controller;

architecture Behavioral of run_controller is

  constant C_BOUND_WIDTH : natural := IMG_WIDTH_BITS + 1; -- extra bit: bound can exceed image width

  signal sInRun     : std_logic;
  signal sRUNval    : unsigned(BITNESS - 1 downto 0);
  signal sRUNcnt    : unsigned(IMG_WIDTH_BITS - 1 downto 0);
  signal sRUNindex  : unsigned(4 downto 0);
  -- sRUNcnt value at which the next A15 '1' bit fires; reset to 2^J[sRUNindex] at each run start
  signal sNextBound : unsigned(C_BOUND_WIDTH - 1 downto 0);

begin

  oRUNval <= sRUNval;

  process (iClk)
    variable vJ         : natural;
    variable vJNext     : natural;
    variable vStep      : unsigned(C_BOUND_WIDTH - 1 downto 0);
    variable vStepNext  : unsigned(C_BOUND_WIDTH - 1 downto 0);
    variable vNewCnt    : unsigned(IMG_WIDTH_BITS - 1 downto 0);
    variable vPrevBound : unsigned(C_BOUND_WIDTH - 1 downto 0);
    variable vResidue   : unsigned(C_BOUND_WIDTH - 1 downto 0);
    variable vBoundHit  : boolean;
  begin
    if rising_edge(iClk) then

      oBpValid     <= '0';
      oBpSuffixLen <= (others => '0');
      oBpSuffixVal <= (others => '0');
      oTokenValid  <= '0';
      oTokenIsRI   <= '0';
      oTokenIx     <= iIx;
      oTokenRa     <= iRa;
      oTokenRb     <= iRb;
      oTokenRc     <= iRc;

      if iRst = '1' then
        sInRun     <= '0';
        sRUNval    <= (others => '0');
        sRUNcnt    <= (others => '0');
        sRUNindex  <= (others => '0');
        sNextBound <= to_unsigned(1, C_BOUND_WIDTH);

      elsif iValid = '1' then

        vJ := CO_J_TABLE(to_integer(sRUNindex));
        if sRUNindex < 31 then
          vJNext := CO_J_TABLE(to_integer(sRUNindex) + 1);
        else
          vJNext := CO_J_TABLE(31);
        end if;
        vStep     := shift_left(to_unsigned(1, C_BOUND_WIDTH), vJ);
        vStepNext := shift_left(to_unsigned(1, C_BOUND_WIDTH), vJNext);

        if sInRun = '1' then

          if iRunContinues = '1' then
            -------------------------------------------------------------------
            -- Case A: in run, run continues
            -------------------------------------------------------------------
            vNewCnt   := sRUNcnt + 1;
            vBoundHit := resize(vNewCnt, C_BOUND_WIDTH) = sNextBound;
            sRUNcnt   <= vNewCnt;

            if vBoundHit then -- A15
              oBpValid     <= '1';
              oBpSuffixLen <= to_unsigned(1, CO_SUFFIXLEN_WIDTH_STD);
              oBpSuffixVal <= to_unsigned(1, CO_SUFFIX_WIDTH_STD);
              if sRUNindex < 31 then
                sRUNindex  <= sRUNindex + 1;
                sNextBound <= sNextBound + vStepNext;
              end if;
            end if;

            if iEOLine = '1' and not vBoundHit then -- A16 EOLine partial segment
              oBpValid     <= '1';
              oBpSuffixLen <= to_unsigned(1, CO_SUFFIXLEN_WIDTH_STD);
              oBpSuffixVal <= to_unsigned(1, CO_SUFFIX_WIDTH_STD);
            end if;

            if iEOLine = '1' then
              sInRun  <= '0';
              sRUNcnt <= (others => '0');
            end if;

          else
            -------------------------------------------------------------------
            -- Case B: run breaks
            -------------------------------------------------------------------
            -- vResidue < 2^J, so bit J of the J+1-bit suffix is '0' (break indicator)
            vPrevBound   := sNextBound - vStep;
            vResidue     := resize(sRUNcnt, C_BOUND_WIDTH) - vPrevBound;
            oBpValid     <= '1';
            oBpSuffixLen <= to_unsigned(vJ + 1, CO_SUFFIXLEN_WIDTH_STD);
            oBpSuffixVal <= vResidue(CO_SUFFIX_WIDTH_STD - 1 downto 0);
            if sRUNindex > 0 then
              sRUNindex <= sRUNindex - 1;
            end if;
            sInRun      <= '0';
            sRUNcnt     <= (others => '0');
            oTokenValid <= '1';
            oTokenIsRI  <= '1';

          end if;

        else

          if iModeIsRun = '1' then
            -----------------------------------------------------------------
            -- Case C: entering run
            -----------------------------------------------------------------
            sRUNval   <= iRa;
            sRUNcnt   <= to_unsigned(1, sRUNcnt'length);
            vBoundHit := vStep = to_unsigned(1, C_BOUND_WIDTH); -- J=0

            if vBoundHit then -- A15 on first pixel
              oBpValid     <= '1';
              oBpSuffixLen <= to_unsigned(1, CO_SUFFIXLEN_WIDTH_STD);
              oBpSuffixVal <= to_unsigned(1, CO_SUFFIX_WIDTH_STD);
              if sRUNindex < 31 then
                sRUNindex  <= sRUNindex + 1;
                sNextBound <= vStep + vStepNext;
              else
                sNextBound <= vStep;
              end if;
            else
              sNextBound <= vStep;
            end if;

            if iEOLine = '1' and not vBoundHit then -- A16 EOLine partial segment
              oBpValid     <= '1';
              oBpSuffixLen <= to_unsigned(1, CO_SUFFIXLEN_WIDTH_STD);
              oBpSuffixVal <= to_unsigned(1, CO_SUFFIX_WIDTH_STD);
            end if;

            if iEOLine = '1' then
              sInRun  <= '0';
              sRUNcnt <= (others => '0');
            else
              sInRun <= '1';
            end if;

          else
            -----------------------------------------------------------------
            -- Case D: regular mode
            -----------------------------------------------------------------
            oTokenValid <= '1';
            oTokenIsRI  <= '0';

          end if;

        end if;

        if iEOI = '1' then
          sInRun     <= '0';
          sRUNcnt    <= (others => '0');
          sRUNindex  <= (others => '0');
          sNextBound <= to_unsigned(1, C_BOUND_WIDTH);
        end if;

      end if;
    end if;
  end process;

end Behavioral;
