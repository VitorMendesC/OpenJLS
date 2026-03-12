----------------------------------------------------------------------------------
-- Engineer:    Vitor Mendes Camilo
--
-- Module Name: jls_framer - Behavioral
-- Description:
--
--   Wraps the byte-stuffed compressed payload with JPEG-LS framing markers:
--     SOI + SOF55 + SOS  (before data)
--     EOI                (after data)
--
--   IN_WIDTH  : word width from byte_stuffer  (CO_BYTE_STUFFER_IN_WIDTH = 24b)
--   OUT_WIDTH : final output word width        (CO_OUT_WIDTH_STD = 72b, min 32b)
--
--   Header emission is triggered by iStart (first pixel entering the encoder
--   pipeline).  BYTES_OUT header bytes are pushed into the accumulator per cycle,
--   so HEADER state lasts ceil(25 / BYTES_OUT) cycles.  Combined with FOOTER
--   (1 cycle) and FINAL_FLUSH (~2 cycles), the oBsReady='0' window is ~6 cycles
--   at 72b output, comfortably within CO_BUFFER_WIDTH_STD = 96b at typical rates.
--
--   Accumulator: 2*OUT_WIDTH-bit byte queue, MSB = head.
--   Worst-case fill: (BYTES_OUT-1) + BYTES_IN < 2*BYTES_OUT (since OUT >= IN).
----------------------------------------------------------------------------------
use work.Common.all;

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

library openlogic_base;
use openlogic_base.olo_base_pkg_math.log2ceil;

entity jls_framer is
  generic (
    NEAR             : natural := CO_NEAR_STD;
    BITNESS          : natural := CO_BITNESS_STD;
    IN_WIDTH         : natural := CO_BYTE_STUFFER_IN_WIDTH;  -- from byte_stuffer
    OUT_WIDTH        : natural := CO_OUT_WIDTH_STD;           -- to AXI-S output
    MAX_IMAGE_WIDTH  : natural := 4096;
    MAX_IMAGE_HEIGHT : natural := 4096
  );
  port (
    iClk         : in  std_logic;
    iRst         : in  std_logic;
    -- Image control
    iStart       : in  std_logic;
    iImageWidth  : in  unsigned(log2ceil(MAX_IMAGE_WIDTH  + 1) - 1 downto 0);
    iImageHeight : in  unsigned(log2ceil(MAX_IMAGE_HEIGHT + 1) - 1 downto 0);
    iEOI         : in  std_logic;
    -- Byte stuffer interface (IN_WIDTH wide)
    iBsWord       : in  std_logic_vector(IN_WIDTH  - 1 downto 0);
    iBsWordValid  : in  std_logic;
    iBsValidBytes : in  unsigned(log2ceil(IN_WIDTH  / 8) downto 0);
    oBsReady      : out std_logic;
    oBsFlush      : out std_logic;
    -- Output (OUT_WIDTH wide)
    oWord         : out std_logic_vector(OUT_WIDTH - 1 downto 0);
    oWordValid    : out std_logic;
    oValidBytes   : out unsigned(log2ceil(OUT_WIDTH / 8) downto 0);
    iReady        : in  std_logic
  );
end jls_framer;

architecture Behavioral of jls_framer is

  constant BYTES_IN     : natural := IN_WIDTH  / 8;
  constant BYTES_OUT    : natural := OUT_WIDTH / 8;
  constant BUFFER_BYTES : natural := 2 * BYTES_OUT;
  constant BUFFER_WIDTH : natural := BUFFER_BYTES * 8;
  constant HEADER_LEN   : natural := 25;

  type fsm_t is (IDLE, HEADER, DATA, FLUSH_BS, FOOTER, FINAL_FLUSH);
  signal sFsmState : fsm_t := IDLE;

  signal sBuffer    : std_logic_vector(BUFFER_WIDTH - 1 downto 0) := (others => '0');
  signal sByteCount : natural range 0 to BUFFER_BYTES             := 0;

  signal sOutWord    : std_logic_vector(OUT_WIDTH - 1 downto 0)      := (others => '0');
  signal sOutValid   : std_logic                                      := '0';
  signal sValidBytes : unsigned(log2ceil(OUT_WIDTH / 8) downto 0)    := (others => '0');

  signal sWidth  : unsigned(15 downto 0) := (others => '0');
  signal sHeight : unsigned(15 downto 0) := (others => '0');

  -- Byte offset into header; increments by BYTES_OUT per cycle
  signal sHeaderByteIdx : natural range 0 to HEADER_LEN := 0;
  -- Guards FLUSH_BS->FOOTER: wait 1 cycle after asserting oBsFlush
  signal sFlushSettled  : std_logic := '0';

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
      when 8      => return std_logic_vector(height(7  downto 0));
      when 9      => return std_logic_vector(width(15 downto 8));
      when 10     => return std_logic_vector(width(7  downto 0));
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

  assert IN_WIDTH  mod 8 = 0
    report "jls_framer: IN_WIDTH must be a multiple of 8"  severity failure;
  assert OUT_WIDTH mod 8 = 0
    report "jls_framer: OUT_WIDTH must be a multiple of 8" severity failure;
  assert OUT_WIDTH >= IN_WIDTH
    report "jls_framer: OUT_WIDTH must be >= IN_WIDTH"     severity failure;

  sAxiHandshake <= (iReady and sOutValid) = '1';

  oWord       <= sOutWord;
  oWordValid  <= sOutValid;
  oValidBytes <= sValidBytes;

  oBsFlush <= '1' when sFsmState = FLUSH_BS else '0';
  -- Accept from byte stuffer when accumulator has room for one more IN word
  oBsReady <= '1' when (sFsmState = DATA or sFsmState = FLUSH_BS)
                       and sByteCount + BYTES_IN <= BUFFER_BYTES else '0';

  process (iClk)
    variable vBuf       : std_logic_vector(BUFFER_WIDTH - 1 downto 0);
    variable vCount     : natural range 0 to BUFFER_BYTES;
    variable vPushCount : natural range 0 to BYTES_OUT;
  begin
    if rising_edge(iClk) then
      if iRst = '1' then
        sFsmState      <= IDLE;
        sBuffer        <= (others => '0');
        sByteCount     <= 0;
        sOutWord       <= (others => '0');
        sOutValid      <= '0';
        sValidBytes    <= (others => '0');
        sWidth         <= (others => '0');
        sHeight        <= (others => '0');
        sHeaderByteIdx <= 0;
        sFlushSettled  <= '0';
      else

        vBuf       := sBuffer;
        vCount     := sByteCount;
        vPushCount := 0;

        ----------------------------------------------------------------
        -- POP: drain accumulator → output register
        ----------------------------------------------------------------
        if vCount >= BYTES_OUT and (sAxiHandshake or sOutValid = '0') then
          sOutWord    <= vBuf(BUFFER_WIDTH - 1 downto BUFFER_WIDTH - OUT_WIDTH);
          sValidBytes <= to_unsigned(BYTES_OUT, sValidBytes'length);
          sOutValid   <= '1';
          vBuf        := std_logic_vector(shift_left(unsigned(vBuf), OUT_WIDTH));
          vCount      := vCount - BYTES_OUT;

        elsif sFsmState = FINAL_FLUSH and vCount > 0
              and (sAxiHandshake or sOutValid = '0') then
          sOutWord    <= vBuf(BUFFER_WIDTH - 1 downto BUFFER_WIDTH - OUT_WIDTH);
          sValidBytes <= to_unsigned(vCount, sValidBytes'length);
          sOutValid   <= '1';
          vBuf        := (others => '0');
          vCount      := 0;

        elsif sAxiHandshake then
          sOutValid <= '0';
        end if;

        ----------------------------------------------------------------
        -- FSM + push source selection (push uses post-pop vCount)
        ----------------------------------------------------------------
        case sFsmState is

          when IDLE =>
            sFlushSettled <= '0';
            if iStart = '1' then
              sWidth         <= resize(iImageWidth,  16);
              sHeight        <= resize(iImageHeight, 16);
              sHeaderByteIdx <= 0;
              sFsmState      <= HEADER;
            end if;

          when HEADER =>
            -- Push up to BYTES_OUT header bytes per cycle.
            -- Stalls only under downstream backpressure.
            if vCount + BYTES_OUT <= BUFFER_BYTES then
              for i in 0 to BYTES_OUT - 1 loop
                if sHeaderByteIdx + i < HEADER_LEN then
                  vBuf(BUFFER_WIDTH - 1 - (vCount + i) * 8 downto
                       BUFFER_WIDTH     - (vCount + i) * 8 - 8)
                    := get_header_byte(sHeaderByteIdx + i, sWidth, sHeight);
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
            -- Pass IN_WIDTH-wide byte stuffer words through the accumulator.
            if iBsWordValid = '1' and sByteCount + BYTES_IN <= BUFFER_BYTES then
              for i in 0 to BYTES_IN - 1 loop
                vBuf(BUFFER_WIDTH - 1 - (vCount + i) * 8 downto
                     BUFFER_WIDTH     - (vCount + i) * 8 - 8)
                  := iBsWord(IN_WIDTH - 1 - i * 8 downto IN_WIDTH - (i + 1) * 8);
              end loop;
              vPushCount := BYTES_IN;
            end if;
            if iEOI = '1' then
              sFsmState <= FLUSH_BS;
            end if;

          when FLUSH_BS =>
            -- Assert oBsFlush (combinatorial). Wait 1 cycle (sFlushSettled) before
            -- transitioning on iBsWordValid='0' so the byte stuffer can react.
            sFlushSettled <= '1';
            if iBsWordValid = '1' and sByteCount + BYTES_IN <= BUFFER_BYTES then
              for i in 0 to BYTES_IN - 1 loop
                if i < to_integer(iBsValidBytes) then
                  vBuf(BUFFER_WIDTH - 1 - (vCount + i) * 8 downto
                       BUFFER_WIDTH     - (vCount + i) * 8 - 8)
                    := iBsWord(IN_WIDTH - 1 - i * 8 downto IN_WIDTH - (i + 1) * 8);
                end if;
              end loop;
              vPushCount := to_integer(iBsValidBytes);
              -- Partial word = final flushed word from byte stuffer
              if to_integer(iBsValidBytes) < BYTES_IN then
                sFsmState <= FOOTER;
              end if;
            elsif iBsWordValid = '0' and sFlushSettled = '1' then
              sFsmState <= FOOTER;
            end if;

          when FOOTER =>
            -- Push EOI in one cycle: FF then D9.
            -- Pop fires first if vCount >= BYTES_OUT, ensuring room.
            sFlushSettled <= '0';
            if vCount + 2 <= BUFFER_BYTES then
              vBuf(BUFFER_WIDTH - 1 -  vCount      * 8 downto
                   BUFFER_WIDTH     -  vCount      * 8 - 8) := x"FF";
              vBuf(BUFFER_WIDTH - 1 - (vCount + 1) * 8 downto
                   BUFFER_WIDTH     - (vCount + 1) * 8 - 8) := x"D9";
              vPushCount := 2;
              sFsmState  <= FINAL_FLUSH;
            end if;

          when FINAL_FLUSH =>
            if sByteCount = 0 and sOutValid = '0' then
              sFsmState <= IDLE;
            end if;

        end case;

        vCount := vCount + vPushCount;
        sBuffer    <= vBuf;
        sByteCount <= vCount;

      end if;
    end if;
  end process;

end Behavioral;
