----------------------------------------------------------------------------------
-- Engineer:    Vitor Mendes Camilo
--
-- Module Name: jls_framer - Behavioral
-- Description:
--
--   Wraps the byte-stuffed compressed payload with JPEG-LS framing markers:
--     SOI + SOF55 + SOS  (header, 25 bytes, before data)
--     EOI = FF D9        (footer, 2 bytes, after data)
--
--   Sits downstream of byte_stuffer.  Does NOT issue a flush upstream; the
--   bit-packer/byte-stuffer flush is driven by the pipelined EOI signal.
--   The top level delays iEOI by one cycle relative to byte_stuffer.iFlush,
--   so iEOI arrives at the framer simultaneously with the byte_stuffer's
--   registered flush output on oWordValid / oValidBytes.
--
--   iEOI protocol (1-cycle pulse):
--     - If iBsWordValid='1' on the same cycle, that word is the last payload
--       word; iBsValidBytes indicates how many bytes are meaningful.
--     - If iBsWordValid='0', the byte_stuffer had nothing buffered to flush.
--     - In both cases the framer appends FF D9 and drains the accumulator,
--       asserting oLast on the final output word (AXI tlast).
--
--   Back-to-back images: iStart for the next image may arrive the cycle
--   immediately after iEOI.  The header is not emitted until the current
--   image (footer included) has been fully drained.
--
--   Image dimensions are fixed at reset by the top level and read directly
--   from the ports without registering.
--
--   IN_WIDTH  : word width from byte_stuffer  (CO_BYTE_STUFFER_IN_WIDTH = 24b)
--   OUT_WIDTH : final output word width        (CO_OUT_WIDTH_STD = 72b)
--
--   Accumulator: 2*OUT_WIDTH-bit byte queue, MSB = head.
----------------------------------------------------------------------------------
use work.Common.all;

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

library openlogic_base;
use openlogic_base.olo_base_pkg_math.log2ceil;

entity jls_framer is
  generic (
    BITNESS          : natural := CO_BITNESS_STD;
    IN_WIDTH         : natural := CO_BYTE_STUFFER_IN_WIDTH; -- from byte_stuffer
    OUT_WIDTH        : natural := CO_OUT_WIDTH_STD;         -- to AXI-S output
    MAX_IMAGE_WIDTH  : natural := 4096;
    MAX_IMAGE_HEIGHT : natural := 4096
  );
  port (
    iClk : in std_logic;
    iRst : in std_logic;
    -- Image control
    iStart       : in std_logic;
    iImageWidth  : in unsigned(log2ceil(MAX_IMAGE_WIDTH + 1) - 1 downto 0);
    iImageHeight : in unsigned(log2ceil(MAX_IMAGE_HEIGHT + 1) - 1 downto 0);
    iEOI         : in std_logic;
    -- Byte stuffer interface (IN_WIDTH wide)
    iBsWord       : in std_logic_vector(IN_WIDTH - 1 downto 0);
    iBsWordValid  : in std_logic;
    iBsValidBytes : in unsigned(log2ceil(IN_WIDTH / 8) downto 0);
    oBsReady      : out std_logic;
    -- Output (OUT_WIDTH wide, AXI-Stream)
    oWord       : out std_logic_vector(OUT_WIDTH - 1 downto 0);
    oWordValid  : out std_logic;
    oValidBytes : out unsigned(log2ceil(OUT_WIDTH / 8) downto 0);
    oLast       : out std_logic;
    iReady      : in std_logic
  );
end jls_framer;

architecture Behavioral of jls_framer is

  constant NEAR         : natural := 0;
  constant BYTES_IN     : natural := IN_WIDTH / 8;
  constant BYTES_OUT    : natural := OUT_WIDTH / 8;
  constant BUFFER_BYTES : natural := 2 * BYTES_OUT;
  constant BUFFER_WIDTH : natural := BUFFER_BYTES * 8;
  constant HEADER_LEN   : natural := 25;

  type fsm_t is (IDLE, HEADER, DATA, FOOTER, FINAL_FLUSH);
  signal sFsmState : fsm_t := IDLE;

  signal sBuffer    : std_logic_vector(BUFFER_WIDTH - 1 downto 0) := (others => '0');
  signal sByteCount : natural range 0 to BUFFER_BYTES             := 0;

  signal sOutWord    : std_logic_vector(OUT_WIDTH - 1 downto 0)   := (others => '0');
  signal sOutValid   : std_logic                                  := '0';
  signal sOutLast    : std_logic                                  := '0';
  signal sValidBytes : unsigned(log2ceil(OUT_WIDTH / 8) downto 0) := (others => '0');

  -- Byte offset into header; increments by BYTES_OUT per cycle
  signal sHeaderByteIdx : natural range 0 to HEADER_LEN := 0;

  -- Set when iStart arrives during FOOTER / FINAL_FLUSH so it isn't missed
  signal sNextPending : std_logic := '0';

  signal sAxiHandshake : boolean;

  -- Returns the i-th byte of the 25-byte JPEG-LS frame header.
  -- Header layout:
  --   [0-1]   FF D8              SOI
  --   [2-5]   FF F7 00 0B        SOF55 marker + Lf=11
  --   [6]     P                  precision (BITNESS)
  --   [7-8]   Y[15:8] Y[7:0]    image height (runtime)
  --   [9-10]  X[15:8] X[7:0]    image width  (runtime)
  --   [11]    01                 Nf=1
  --   [12-14] 01 11 00           C1=1, H1V1=0x11, Tq1=0
  --   [15-16] FF DA              SOS marker
  --   [17-18] 00 08              Ls=8
  --   [19]    01                 Ns=1
  --   [20-21] 01 00              Cs1=1, Tm1=0
  --   [22]    NEAR
  --   [23-24] 00 00              ILV=0, Al/Ah=0
  function get_header_byte(
    idx    : natural;
    width  : unsigned(15 downto 0);
    height : unsigned(15 downto 0)
  ) return std_logic_vector is
  begin
    case idx is
      when 0      => return x"FF";
      when 1      => return x"D8";
      when 2      => return x"FF";
      when 3      => return x"F7";
      when 4      => return x"00";
      when 5      => return x"0B";
      when 6      => return std_logic_vector(to_unsigned(BITNESS, 8));
      when 7      => return std_logic_vector(height(15 downto 8));
      when 8      => return std_logic_vector(height(7 downto 0));
      when 9      => return std_logic_vector(width(15 downto 8));
      when 10     => return std_logic_vector(width(7 downto 0));
      when 11     => return x"01";
      when 12     => return x"01";
      when 13     => return x"11";
      when 14     => return x"00";
      when 15     => return x"FF";
      when 16     => return x"DA";
      when 17     => return x"00";
      when 18     => return x"08";
      when 19     => return x"01";
      when 20     => return x"01";
      when 21     => return x"00";
      when 22     => return std_logic_vector(to_unsigned(NEAR, 8));
      when 23     => return x"00";
      when 24     => return x"00";
      when others => return x"00";
    end case;
  end function;

begin

  assert IN_WIDTH mod 8 = 0
  report "jls_framer: IN_WIDTH must be a multiple of 8" severity failure;
  assert OUT_WIDTH mod 8 = 0
  report "jls_framer: OUT_WIDTH must be a multiple of 8" severity failure;
  assert OUT_WIDTH >= IN_WIDTH
  report "jls_framer: OUT_WIDTH must be >= IN_WIDTH" severity failure;

  sAxiHandshake <= (iReady and sOutValid) = '1';

  oWord       <= sOutWord;
  oWordValid  <= sOutValid;
  oValidBytes <= sValidBytes;
  oLast       <= sOutLast;

  -- Accept from byte stuffer only in DATA state and when accumulator has room.
  -- Uses registered sByteCount (conservative): the byte stuffer only presents
  -- valid data after seeing oBsReady='1', so sByteCount + BYTES_IN <= BUFFER_BYTES
  -- is guaranteed to hold whenever iBsWordValid='1'.
  oBsReady                  <= '1' when sFsmState = DATA
    and sByteCount + BYTES_IN <= BUFFER_BYTES else
    '0';

  process (iClk)
    variable vBuf       : std_logic_vector(BUFFER_WIDTH - 1 downto 0);
    variable vCount     : natural range 0 to BUFFER_BYTES;
    variable vPushCount : natural range 0 to BYTES_OUT;
    variable vWidth     : unsigned(15 downto 0);
    variable vHeight    : unsigned(15 downto 0);
  begin
    if rising_edge(iClk) then
      if iRst = '1' then
        sFsmState      <= IDLE;
        sBuffer        <= (others => '0');
        sByteCount     <= 0;
        sOutWord       <= (others => '0');
        sOutValid      <= '0';
        sOutLast       <= '0';
        sValidBytes    <= (others => '0');
        sHeaderByteIdx <= 0;
        sNextPending   <= '0';
      else

        vBuf       := sBuffer;
        vCount     := sByteCount;
        vPushCount := 0;
        vWidth     := resize(iImageWidth, 16);
        vHeight    := resize(iImageHeight, 16);

        ----------------------------------------------------------------
        -- POP: drain accumulator → output register (fires first so the
        -- push section below sees the post-pop vCount)
        ----------------------------------------------------------------
        if vCount >= BYTES_OUT and (sAxiHandshake or sOutValid = '0') then
          -- Full word; oLast when this is the last word in FINAL_FLUSH
          sOutWord    <= vBuf(BUFFER_WIDTH - 1 downto BUFFER_WIDTH - OUT_WIDTH);
          sValidBytes <= to_unsigned(BYTES_OUT, sValidBytes'length);
          sOutValid   <= '1';
          sOutLast    <= bool2bit(sFsmState = FINAL_FLUSH and vCount = BYTES_OUT);
          vBuf   := std_logic_vector(shift_left(unsigned(vBuf), OUT_WIDTH));
          vCount := vCount - BYTES_OUT;

        elsif sFsmState = FINAL_FLUSH and vCount > 0
          and (sAxiHandshake or sOutValid = '0') then
          -- Partial last word of the image
          sOutWord    <= vBuf(BUFFER_WIDTH - 1 downto BUFFER_WIDTH - OUT_WIDTH);
          sValidBytes <= to_unsigned(vCount, sValidBytes'length);
          sOutValid   <= '1';
          sOutLast    <= '1';
          vBuf   := (others => '0');
          vCount := 0;

        elsif sAxiHandshake then
          sOutValid <= '0';
          sOutLast  <= '0';
        end if;

        ----------------------------------------------------------------
        -- FSM + push (uses post-pop vCount / vBuf)
        ----------------------------------------------------------------
        case sFsmState is

          when IDLE =>
            if iStart = '1' then
              sHeaderByteIdx <= 0;
              sFsmState      <= HEADER;
            end if;

          when HEADER =>
            -- Push up to BYTES_OUT header bytes per cycle.
            if vCount + BYTES_OUT <= BUFFER_BYTES then
              for i in 0 to BYTES_OUT - 1 loop
                if sHeaderByteIdx + i < HEADER_LEN then
                  vBuf(BUFFER_WIDTH - 1 - (vCount + i) * 8 downto
                  BUFFER_WIDTH - (vCount + i) * 8 - 8)
                  := get_header_byte(sHeaderByteIdx + i, vWidth, vHeight);
                  vPushCount := vPushCount + 1;
                end if;
              end loop;
              if sHeaderByteIdx + BYTES_OUT >= HEADER_LEN then
                sFsmState <= DATA;
              else
                sHeaderByteIdx <= sHeaderByteIdx + BYTES_OUT;
              end if;
            end if;

          when DATA =>
            -- Pass byte-stuffer words into the accumulator.
            -- On iEOI, the arriving word (if valid) is the last payload word
            -- (byte_stuffer's registered flush output); use iBsValidBytes to
            -- push only the meaningful bytes.
            if iBsWordValid = '1' and vCount + BYTES_IN <= BUFFER_BYTES then
              if iEOI = '1' then
                for i in 0 to BYTES_IN - 1 loop
                  if i < to_integer(iBsValidBytes) then
                    vBuf(BUFFER_WIDTH - 1 - (vCount + i) * 8 downto
                    BUFFER_WIDTH - (vCount + i) * 8 - 8)
                    := iBsWord(IN_WIDTH - 1 - i * 8 downto IN_WIDTH - (i + 1) * 8);
                  end if;
                end loop;
                vPushCount := to_integer(iBsValidBytes);
              else
                for i in 0 to BYTES_IN - 1 loop
                  vBuf(BUFFER_WIDTH - 1 - (vCount + i) * 8 downto
                  BUFFER_WIDTH - (vCount + i) * 8 - 8)
                  := iBsWord(IN_WIDTH - 1 - i * 8 downto IN_WIDTH - (i + 1) * 8);
                end loop;
                vPushCount := BYTES_IN;
              end if;
            end if;
            if iEOI = '1' then
              sFsmState <= FOOTER;
            end if;

          when FOOTER =>
            -- Latch iStart that may arrive while stalled waiting for buffer room
            if iStart = '1' then
              sNextPending <= '1';
            end if;
            -- Append 2-byte EOI marker FF D9.
            -- The pop above may have freed space; stall here if not yet.
            if vCount + 2 <= BUFFER_BYTES then
              vBuf(BUFFER_WIDTH - 1 - vCount * 8 downto
              BUFFER_WIDTH - vCount * 8 - 8) := x"FF";
              vBuf(BUFFER_WIDTH - 1 - (vCount + 1) * 8 downto
              BUFFER_WIDTH - (vCount + 1) * 8 - 8) := x"D9";
              vPushCount                           := 2;
              sFsmState <= FINAL_FLUSH;
            end if;

          when FINAL_FLUSH =>
            -- Latch iStart arriving before the drain completes
            if iStart = '1' then
              sNextPending <= '1';
            end if;
            -- Transition once the accumulator is empty and the output
            -- register has been consumed by downstream (oLast handshake done).
            if sByteCount = 0 and sOutValid = '0' then
              sNextPending <= '0';
              if sNextPending = '1' or iStart = '1' then
                sHeaderByteIdx <= 0;
                sFsmState      <= HEADER;
              else
                sFsmState <= IDLE;
              end if;
            end if;

        end case;

        vCount := vCount + vPushCount;
        sBuffer    <= vBuf;
        sByteCount <= vCount;

      end if;
    end if;
  end process;

end Behavioral;
