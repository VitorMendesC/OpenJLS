----------------------------------------------------------------------------------
-- Company:
-- Engineer:    Vitor Mendes Camilo
--
-- Create Date:
-- Module Name: line_buffer - Behavioral
-- Description:
--
-- Notes:
--              Stores one row of pixels and provides the four T.87 causal
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
--                First row      : b = c = d = 0, a = 0
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
    iClk : in std_logic;
    iRst : in std_logic;
    -- Runtime image dimensions
    iImageWidth  : in unsigned(log2ceil(MAX_IMAGE_WIDTH + 1) - 1 downto 0);
    iImageHeight : in unsigned(log2ceil(MAX_IMAGE_HEIGHT + 1) - 1 downto 0);
    iValid       : in std_logic;
    iPixel       : in unsigned(BITNESS - 1 downto 0);

    oA        : out unsigned(BITNESS - 1 downto 0);
    oB        : out unsigned(BITNESS - 1 downto 0);
    oC        : out unsigned(BITNESS - 1 downto 0);
    oD        : out unsigned(BITNESS - 1 downto 0);
    oValid    : out std_logic;
    oFirstRow : out std_logic; -- high throughout row 0; b=c=d=0
    oEOL      : out std_logic; -- end-of-line: last pixel of current row
    oEOI      : out std_logic -- end-of-image: last pixel of last row
  );
end entity line_buffer;

architecture Behavioral of line_buffer is

  constant COL_WIDTH : natural := log2ceil(MAX_IMAGE_WIDTH + 1);
  constant ROW_WIDTH : natural := log2ceil(MAX_IMAGE_HEIGHT + 1);

  type fifo_state_t is (PRELOAD, WAIT_END_FIRST_ROW, NOMINAL);
  signal sFifoState : fifo_state_t;

  -- FIFO: holds the previous row
  signal sFifoRst      : std_logic; -- iRst OR combinatorial reset at EOI
  signal sFifoOutReady : std_logic;
  signal sFifoOutValid : std_logic;
  signal sFifoOutData  : std_logic_vector(BITNESS - 1 downto 0);
  signal sFifoFull     : std_logic;
  signal sFifoEmpty    : std_logic;

  signal sD : unsigned(BITNESS - 1 downto 0); -- d: upper-right
  signal sB : unsigned(BITNESS - 1 downto 0); -- b: upper
  signal sC : unsigned(BITNESS - 1 downto 0); -- c: upper-left
  signal sA : unsigned(BITNESS - 1 downto 0); -- a: left

  signal sColCounter : unsigned(COL_WIDTH - 1 downto 0);
  signal sRowCounter : unsigned(ROW_WIDTH - 1 downto 0);

  signal sIsLastCol          : boolean;
  signal sIsLastRow          : boolean;
  signal sIsEoi              : boolean;
  signal sIsEol              : boolean;
  signal sIsFifoOutHandshake : boolean;

  signal sPreloadCounter : unsigned(1 downto 0); -- counts preloading previous row pixels

begin

  -- Positional signals --------------------------------------------------------------------
  sIsLastCol          <= sColCounter = iImageWidth - 1;
  sIsLastRow          <= sRowCounter = iImageHeight - 1;
  sIsEol              <= sIsLastCol and iValid = '1';
  sIsEoi              <= sIsLastCol and sIsLastRow and iValid = '1';
  sIsFifoOutHandshake <= (sFifoOutReady and sFifoOutValid) = '1';

  -- Process -------------------------------------------------------------------------------
  process (iClk)
  begin

    if rising_edge(iClk) then
      if iRst = '1' then
        sPreloadCounter <= (others => '0');
        sFifoOutReady   <= '0';
        sFifoState      <= PRELOAD;

        sColCounter <= (others => '0');
        sRowCounter <= (others => '0');

        sB <= (others => '0');
        sC <= (others => '0');
        sD <= (others => '0');
        sA <= (others => '0');

      else

        -- FIFO control FSM ----------------------------
        case sFifoState is

          when PRELOAD =>
            sFifoOutReady <= '1';

            if sIsFifoOutHandshake then
              sPreloadCounter <= sPreloadCounter + 1;
              if sPreloadCounter = 2 then
                sFifoState    <= WAIT_END_FIRST_ROW;
                sFifoOutReady <= '0';
              end if;
            end if;

          when WAIT_END_FIRST_ROW =>
            if sIsEol then
              sFifoState <= NOMINAL;
            end if;

          when NOMINAL =>
            -- On valid operation, every new pixel steps the context window by reading new neighbor pixels
            sFifoOutReady <= iValid;

            if sIsEOI then
              sFifoState      <= PRELOAD; -- Reset FIFO for next image
              sFifoOutReady   <= '0';
              sPreloadCounter <= (others => '0');
            end if;

        end case;

        -- Counters -------------------------------------
        if iValid = '1' then
          if sIsLastCol then
            sColCounter <= (others => '0');
            if not sIsLastRow then
              sRowCounter <= sRowCounter + 1;
            end if;
          else
            sColCounter <= sColCounter + 1;
          end if;
        end if;

        -- Output control -------------------------------
        if sIsFifoOutHandshake then
          sC <= sB;
          sB <= sD;
          sD <= unsigned(sFifoOutData);
        end if;

        if iValid = '1' then
          sA <= iPixel;
        end if;

      end if;
    end if;
  end process;

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
      Rst       => sFifoRst,
      In_Data   => std_logic_vector(iPixel),
      In_Valid  => iValid,
      Out_Ready => sFifoOutReady, -- Read enable
      Out_Data  => sFifoOutData,
      Out_Valid => sFifoOutValid,
      Full      => sFifoFull,
      Empty     => sFifoEmpty
    );

end architecture Behavioral;
