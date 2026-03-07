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
--              context neighbors for each pixel:
--
--                  c  b  d
--                  a  x       (x = current pixel, raster scan left->right)
--
--              a = left neighbor        (same row, col-1)
--              b = upper neighbor       (previous row, col)
--              c = upper-left neighbor  (previous row, col-1)
--              d = upper-right neighbor (previous row, col+1)
--
--              Three pipeline registers (sDCur / sBCur / sCCur) always hold
--              d, b, c simultaneously so all four neighbors are available as
--              registered signals on the same cycle as iValid.
--
--              Border conditions (T.87 A.2.1):
--                First row      : b = c = d = 0, a = 0
--                Col 0 (rows>0) : a = Rb = first pixel of previous row
--                                 c = Ra from start of previous row
--                                   = first pixel of the row before that
--                Col W-1        : d = b (replicate last pixel of previous row)
--
--              Back-to-back streaming:
--                Both rows within an image and consecutive images may be fed
--                with no gap. Pre-pop for the next row is overlapped with
--                cols W-2/W-1 of the current row. At EOI the FIFO is reset
--                combinatorially (the pop result at that cycle is irrelevant
--                since sFirstRow='1' gates oB/oC/oD to 0), so the next
--                image's first pixel may arrive the very next cycle.
--
--              Runtime image dimensions:
--                iImageWidth and iImageHeight set the actual dimensions for
--                the current image. They must be stable before the first
--                iValid and not change mid-image. The generics MAX_IMAGE_WIDTH
--                and MAX_IMAGE_HEIGHT only size the FIFO and counters.
--
-- NOTE:        Near-lossless (NEAR > 0) will require one change here:
--                The FIFO currently stores raw iPixel values. For NEAR > 0
--                it must store the RECONSTRUCTED pixel instead (add a
--                separate iReconstructedPixel input and use it for the
--                FIFO push and sAReg update). Border values (0, Rb) are
--                the same for both lossless and near-lossless (T.87 A.2.1).
--              No change needed for lossless mode (NEAR = 0).
--
-- TODO: investigate CharLS / other JPEG-LS reference implementations for
--       alternative line buffer designs (ring-buffer, dual-read-port RAM).
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
    MAX_IMAGE_WIDTH  : positive;
    MAX_IMAGE_HEIGHT : positive;
    BITNESS          : natural := CO_BITNESS_STD
  );
  port (
    iClk : in std_logic;
    iRst : in std_logic;
    -- Runtime image dimensions (must be stable before first iValid)
    iImageWidth  : in unsigned(log2ceil(MAX_IMAGE_WIDTH + 1) - 1 downto 0);
    iImageHeight : in unsigned(log2ceil(MAX_IMAGE_HEIGHT + 1) - 1 downto 0);
    iValid       : in std_logic;
    iPixel       : in unsigned(BITNESS - 1 downto 0);
    -- Context outputs: valid combinatorially when iValid = '1'
    oA        : out unsigned(BITNESS - 1 downto 0);
    oB        : out unsigned(BITNESS - 1 downto 0);
    oC        : out unsigned(BITNESS - 1 downto 0);
    oD        : out unsigned(BITNESS - 1 downto 0);
    oValid    : out std_logic;
    oFirstRow : out std_logic; -- high throughout row 0; b=c=d=0
    oEOL      : out std_logic; -- end-of-line: last pixel of current row
    oEOI      : out std_logic  -- end-of-image: last pixel of last row
  );
end entity line_buffer;

architecture Behavioral of line_buffer is

  constant C_COL_WIDTH : natural := log2ceil(MAX_IMAGE_WIDTH + 1);
  constant C_ROW_WIDTH : natural := log2ceil(MAX_IMAGE_HEIGHT + 1);

  -- FIFO (OLO olo_base_fifo_sync, FWFT): holds the previous row
  signal sFifoRst      : std_logic; -- iRst OR combinatorial reset at EOI
  signal sFifoInValid  : std_logic;
  signal sFifoInReady  : std_logic;
  signal sFifoOutValid : std_logic;
  signal sFifoOutReady : std_logic; -- pop strobe (combinatorial)
  signal sFifoOutData  : std_logic_vector(BITNESS - 1 downto 0);

  -- Context pipeline registers: never corrupted mid-row by the pre-pop
  signal sDCur : unsigned(BITNESS - 1 downto 0); -- d: upper-right
  signal sBCur : unsigned(BITNESS - 1 downto 0); -- b: upper
  signal sCCur : unsigned(BITNESS - 1 downto 0); -- c: upper-left
  signal sAReg : unsigned(BITNESS - 1 downto 0); -- a: left

  -- Captures x[0] of the current row at col W-2; seeds b/a at col 0 of next row
  signal sDStaging : unsigned(BITNESS - 1 downto 0);

  -- Holds x[0] of the row before the previous row; used as c at col 0 (T.87 A.2.1)
  signal sRaPrev : unsigned(BITNESS - 1 downto 0);

  type state_t is (ST_IDLE, ST_ACTIVE);
  signal sState : state_t;

  signal sColCounter : unsigned(C_COL_WIDTH - 1 downto 0);
  signal sRowCounter : unsigned(C_ROW_WIDTH - 1 downto 0);
  signal sFirstRow   : std_logic; -- cleared after row 0's last pixel

  signal sIsLastCol       : boolean;
  signal sIsSecondLastCol : boolean;
  signal sIsPopCol        : boolean;
  signal sIsLastRow       : boolean;

begin

  assert MAX_IMAGE_WIDTH >= 3
  report "line_buffer: MAX_IMAGE_WIDTH must be >= 3"
    severity failure;

  sIsLastCol       <= sColCounter = iImageWidth - 1;
  sIsSecondLastCol <= sColCounter = iImageWidth - 2;
  sIsPopCol        <= sColCounter < iImageWidth - 2;
  sIsLastRow       <= sRowCounter = iImageHeight - 1;

  -- Reset the FIFO at EOI so the next image can start the very next cycle.
  -- The pop result at col W-1 of the last row is irrelevant: sFirstRow becomes
  -- '1' at the same edge, gating oB/oC/oD to 0 regardless of what is loaded.
  sFifoRst <= '1' when iRst = '1' or
    (sState = ST_ACTIVE and iValid = '1' and sIsLastCol and sIsLastRow) else '0';
  sFifoInValid <= iValid;

  -- cols 0..W-3 (rows 1+): advance pipeline from previous row
  -- col W-2 (all rows): capture x[0] of current row into sDStaging
  -- col W-1 (all rows): x[1] of current row is at FIFO head after col W-2 pop
  sFifoOutReady <=
    '1' when sState = ST_ACTIVE and iValid = '1' and sFirstRow = '0' and sIsPopCol else
    '1' when sState = ST_ACTIVE and iValid = '1' and sIsSecondLastCol else
    '1' when sState = ST_ACTIVE and iValid = '1' and sIsLastCol else
    '0';

  oA <= sAReg;
  oB <= (others => '0') when sFirstRow = '1' else sBCur;
  oC <= (others => '0') when sFirstRow = '1' else sCCur;
  oD <= (others => '0') when sFirstRow = '1' else sDCur;
  oValid    <= iValid;
  oFirstRow <= sFirstRow;

  oEOL <= '1' when sState = ST_ACTIVE and iValid = '1' and sIsLastCol else '0';
  oEOI <= '1' when sState = ST_ACTIVE and iValid = '1' and sIsLastCol and sIsLastRow else '0';

  process (iClk)
  begin
    if rising_edge(iClk) then
      if iRst = '1' then
        sState      <= ST_IDLE;
        sColCounter <= (others => '0');
        sRowCounter <= (others => '0');
        sFirstRow   <= '1';
        sDCur       <= (others => '0');
        sBCur       <= (others => '0');
        sCCur       <= (others => '0');
        sAReg     <= (others => '0');
        sDStaging <= (others => '0');
        sRaPrev   <= (others => '0');

      else
        case sState is

          when ST_IDLE =>
            if iValid = '1' then
              sState      <= ST_ACTIVE;
              sColCounter <= (others => '0');
              sAReg       <= (others => '0'); -- a = 0 at col 0 of every first row
            end if;

          when ST_ACTIVE =>
            if iValid = '1' then

              if sIsLastCol then
                sColCounter <= (others => '0');
                if sIsLastRow then
                  sState      <= ST_IDLE;
                  sFirstRow   <= '1';
                  sRowCounter <= (others => '0');
                else
                  sRowCounter <= sRowCounter + 1;
                end if;
                if sFirstRow = '1' then
                  sFirstRow <= '0';
                end if;
                -- Load context for col 0 of next row from in-band pre-pop.
                -- sAReg = x[0] (Ra = Rb per T.87 A.2.1), not iPixel.
                sBCur   <= sDStaging;
                sDCur   <= unsigned(sFifoOutData);
                sCCur   <= sRaPrev;
                sAReg   <= sDStaging;
                sRaPrev <= sDStaging;               -- becomes c at col 0 two rows later

              elsif sIsSecondLastCol then
                -- Capture x[0] of current row; advance pipeline for this pixel
                sDStaging   <= unsigned(sFifoOutData);
                sAReg       <= iPixel;
                sColCounter <= sColCounter + 1;
                if sFirstRow = '0' then
                  sCCur <= sBCur;
                  sBCur <= sDCur;
                  -- sDCur retains x[W-1] of previous row: d = b at col W-1
                end if;

              else -- cols 0..W-3
                sAReg       <= iPixel;
                sColCounter <= sColCounter + 1;
                if sFirstRow = '0' then
                  sCCur <= sBCur;
                  sBCur <= sDCur;
                  sDCur <= unsigned(sFifoOutData);
                end if;

              end if;

            end if; -- iValid

        end case;
      end if;
    end if;
  end process;

  fifo_inst : entity openlogic_base.olo_base_fifo_sync
    generic map(
      Width_g       => BITNESS,
      Depth_g       => MAX_IMAGE_WIDTH,
      RamBehavior_g => "RBW"
    )
    port map(
      Clk       => iClk,
      Rst       => sFifoRst,
      In_Data   => std_logic_vector(iPixel),
      In_Valid  => sFifoInValid,
      In_Ready  => sFifoInReady,
      Out_Data  => sFifoOutData,
      Out_Valid => sFifoOutValid,
      Out_Ready => sFifoOutReady
    );

end architecture Behavioral;
