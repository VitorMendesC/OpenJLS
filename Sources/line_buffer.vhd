----------------------------------------------------------------------------------
-- Company:
-- Engineer:    Vitor Mendes Camilo
--
-- Create Date:
-- Module Name: line_buffer - Behavioral
-- Description:
--
-- Notes:
--              Stores one row of pixels on FIFO and provides the four T.87 causal
--              context neighbors for each pixel, where x is the current pixel:
--
--                  c  b  d
--                  a  x  
--
--              a = left neighbor        (same row, col-1)
--              b = upper neighbor       (previous row, col)
--              c = upper-left neighbor  (previous row, col-1)
--              d = upper-right neighbor (previous row, col+1)
--
--              Border conditions (T.87 A.2.1):
--                First row      : b = c = d = 0
--                Col 0 (rows>0) : a = Rb = first pixel of previous row
--                                 c = Ra from start of previous row
--                                   = first pixel of the row before that
--                Col W-1        : d = b (replicate last pixel of previous row)
--
--
-- Assumptions:
--              iImageWidth >= 3, iImageHeight >= 1.
--              iImageWidth and iImageHeight are stable for the entire image.
----------------------------------------------------------------------------------
use work.Common.all;

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

library openlogic_base;
use openlogic_base.olo_base_pkg_math.log2ceil;

entity line_buffer is
  generic (
    MAX_IMAGE_WIDTH  : positive range 3 to integer'high;
    MAX_IMAGE_HEIGHT : positive;
    BITNESS          : natural := CO_BITNESS_STD
  );
  port (
    iClk         : in std_logic;
    iRst         : in std_logic;
    iImageWidth  : in unsigned(log2ceil(MAX_IMAGE_WIDTH + 1) - 1 downto 0);
    iImageHeight : in unsigned(log2ceil(MAX_IMAGE_HEIGHT + 1) - 1 downto 0);
    iValid       : in std_logic;
    iPixel       : in unsigned(BITNESS - 1 downto 0);
    oA           : out unsigned(BITNESS - 1 downto 0);
    oB           : out unsigned(BITNESS - 1 downto 0);
    oC           : out unsigned(BITNESS - 1 downto 0);
    oD           : out unsigned(BITNESS - 1 downto 0);
    oValid       : out std_logic;
    oEOL         : out std_logic; -- end of line
    oEOI         : out std_logic -- end of image
  );
end entity line_buffer;

architecture Behavioral of line_buffer is

  constant COL_WIDTH : natural := log2ceil(MAX_IMAGE_WIDTH + 1);
  constant ROW_WIDTH : natural := log2ceil(MAX_IMAGE_HEIGHT + 1);

  type fifo_state_t is (PRELOAD, WAIT_END_FIRST_ROW, NOMINAL);
  signal sFifoState : fifo_state_t;

  signal sFifoRst            : std_logic;
  signal sFifoOutReady       : std_logic;
  signal sFifoOutValid       : std_logic;
  signal sFifoOutData        : std_logic_vector(BITNESS - 1 downto 0);
  signal sFifoFull           : std_logic;
  signal sFifoEmpty          : std_logic;
  signal sD                  : unsigned(BITNESS - 1 downto 0); -- d: upper-right
  signal sB                  : unsigned(BITNESS - 1 downto 0); -- b: upper
  signal sC                  : unsigned(BITNESS - 1 downto 0); -- c: upper-left
  signal sA                  : unsigned(BITNESS - 1 downto 0); -- a: left
  signal sBorderC            : unsigned(BITNESS - 1 downto 0); -- c at col 0: sB captured at col 0 of previous row
  signal sColCounter         : unsigned(COL_WIDTH - 1 downto 0);
  signal sRowCounter         : unsigned(ROW_WIDTH - 1 downto 0);
  signal sIsLastCol          : boolean;
  signal sIsLastRow          : boolean;
  signal sIsEOI              : boolean;
  signal sIsEOL              : boolean;
  signal sIsFifoOutHandshake : boolean;
  signal sIsFirstCol         : boolean;
  signal sPreloadCounter     : unsigned(1 downto 0);

begin

  -- Combinatorial process ----------------------------------------------------------------
  comb_proc : process (all)
  begin
    oValid              <= iValid;
    sIsLastCol          <= sColCounter = iImageWidth - 1;
    sIsLastRow          <= sRowCounter = iImageHeight - 1;
    sIsFirstCol         <= sColCounter = 0;
    sIsEOL              <= sIsLastCol and iValid = '1';
    sIsEOI              <= sIsLastCol and sIsLastRow and iValid = '1';
    oEOI                <= bool2bit(sIsEOI);
    oEOL                <= bool2bit(sIsEOL);
    sIsFifoOutHandshake <= (sFifoOutReady and sFifoOutValid) = '1';

    -- Read FIFO logic ------------------------------------------------------
    sFifoOutReady <= '1' when sFifoState = PRELOAD else
      iValid when sFifoState = NOMINAL else
      '0';

    -- Corner case handling for border conditions (T.87 A.2.1) --------------
    if sRowCounter = 0 then -- First row: b = c = d = 0
      oB <= (others => '0');
      oC <= (others => '0');
      oD <= (others => '0');
    else
      oB <= sB;
      if sIsFirstCol then
        oC <= sBorderC; -- Col 0: c = Ra from start of previous row
      else
        oC <= sC;
      end if;

      if sIsLastCol then
        oD <= sB; -- Last col: replicate last pixel of previous row (= b)
      else
        oD <= sD;
      end if;
    end if;

    if sIsFirstCol then
      oA <= sB; -- First col: replicate first pixel of previous row (= b)
    else
      oA <= sA;
    end if;

  end process; ----------------------------------------------------------------------------

  -- Clocked Process ----------------------------------------------------------------------
  clocked_proc : process (iClk)
  begin

    if rising_edge(iClk) then
      if iRst = '1' then
        sPreloadCounter <= (others => '0');
        sFifoState      <= PRELOAD;
        sFifoRst        <= '0';

        sColCounter <= (others => '0');
        sRowCounter <= (others => '0');

        sB       <= (others => '0');
        sC       <= (others => '0');
        sD       <= (others => '0');
        sA       <= (others => '0');
        sBorderC <= (others => '0');

      else

        sFifoRst <= '0';

        -- FIFO control FSM ----------------------------
        -- sFifoOutReady is controlled combinationally using these states
        case sFifoState is

          when PRELOAD =>
            -- When FIFO receives the first pixels it loads them into registers, preparing for nominal operation
            -- Only loads b and d, since c is out of image

            if sIsFifoOutHandshake then
              sPreloadCounter <= sPreloadCounter + 1;
              if sPreloadCounter = 1 then
                sFifoState <= WAIT_END_FIRST_ROW;
              end if;
            end if;

          when WAIT_END_FIRST_ROW =>
            -- Nominal operation starts only on second row, since first row has no valid context
            if sIsEOL then
              sFifoState <= NOMINAL;
            end if;

          when NOMINAL =>
            -- On valid operation, every new pixel steps the context window by reading a new neighbor pixels and shifting the current ones

            if sIsEOI then
              sFifoState      <= PRELOAD; -- Reset FIFO for next image
              sFifoRst        <= '1';
              sPreloadCounter <= (others => '0');
            end if;

        end case;

        -- Counters -------------------------------------
        if iValid = '1' then
          if sIsLastCol then
            sColCounter <= (others => '0');
            if sIsLastRow then
              sRowCounter <= (others => '0');
            else
              sRowCounter <= sRowCounter + 1;
            end if;
          else
            sColCounter <= sColCounter + 1;
          end if;
        end if;

        -- Output control -------------------------------
        -- Shift context window
        if sIsFifoOutHandshake then
          sC <= sB;
          sB <= sD;
          sD <= unsigned(sFifoOutData);
        end if;

        -- Store last pixel
        if iValid = '1' then
          sA <= iPixel;
          if sColCounter = 0 then
            sBorderC <= sB; -- Capture sB at col 0 for use as c border at col 0 of next row
          end if;
        end if;

      end if;
    end if;
  end process; -----------------------------------------------------------------------------

  -- Instance FIFO -------------------------------------------------------------------------
  fifo_inst : entity openlogic_base.olo_base_fifo_sync
    generic map(
      Width_g       => BITNESS,
      Depth_g       => MAX_IMAGE_WIDTH,
      RamBehavior_g => "RBW"
    )
    port map
    (
      Clk       => iClk,
      Rst       => iRst or sFifoRst,
      In_Data   => std_logic_vector(iPixel),
      In_Valid  => iValid,
      Out_Ready => sFifoOutReady, -- Read FIFO if not empty (valid)
      Out_Data  => sFifoOutData,
      Out_Valid => sFifoOutValid,
      Full      => sFifoFull,
      Empty     => sFifoEmpty
    );

end architecture Behavioral;
