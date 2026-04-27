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
--   Architecture:
--     - One byte FIFO holds payload bytes. The FF D9 footer is pushed into
--       the FIFO right after byte_stuffer's last word on iEOI, so the output
--       side sees footer bytes as ordinary data and oLast falls out naturally.
--     - Header bytes come from a combinational ROM (get_header_byte). The
--       FIFO never stores header bytes.
--     - Output FSM (IDLE / HEADER / DATA) selects header ROM vs FIFO per beat.
--       Splicing handles the partial last header beat (filled from the FIFO)
--       and the partial last data beat (cut at sEndOfImage with oLast).
--     - byte_stuffer is never back-pressured. oBsReady is advisory; the FIFO
--       is sized so that pushes always fit under correct upstream behaviour.
--
--   iEOI (1-cycle pulse): asserts on byte_stuffer's last word for the image.
--   That cycle the framer pushes (iBsValidBytes byte_stuffer bytes) followed
--   by (FF D9), and latches sEndOfImage to the offset (from FIFO head) of the
--   trailing D9. The output FSM watches this offset; when the bytes popped
--   this cycle reach it, oLast asserts on that beat.
--
--   Note: only one sEndOfImage marker is tracked. If image N+1's iEOI arrives
--   before image N's marker has been emitted (only possible for very small
--   images), the marker is clobbered. Promote sEndOfImage to a small FIFO if
--   that case is seen in practice (e.g. the 4x4 image in tb_openjls_top).
--
--   Image dimensions are fixed at reset by the top level and read directly
--   from the ports without registering.
--
--   IN_WIDTH     : word width from byte_stuffer  (CO_BYTE_STUFFER_OUT_WIDTH)
--   OUT_WIDTH    : final output word width        (CO_OUT_WIDTH_STD)
--   BUFFER_BYTES : payload FIFO depth in bytes
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
    IN_WIDTH         : natural := CO_BYTE_STUFFER_OUT_WIDTH;
    OUT_WIDTH        : natural := CO_OUT_WIDTH_STD;
    MAX_IMAGE_WIDTH  : natural := 4096;
    MAX_IMAGE_HEIGHT : natural := 4096;
    BUFFER_BYTES     : natural := 48
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
    iBsValidBytes : in unsigned(log2ceil(IN_WIDTH / 8 + 1) - 1 downto 0);
    oBsReady      : out std_logic;
    -- Output (OUT_WIDTH wide, AXI-Stream)
    oWord       : out std_logic_vector(OUT_WIDTH - 1 downto 0);
    oWordValid  : out std_logic;
    oValidBytes : out unsigned(log2ceil(OUT_WIDTH / 8 + 1) - 1 downto 0);
    oLast       : out std_logic;
    iReady      : in std_logic
  );
end jls_framer;

architecture Behavioral of jls_framer is

  constant NEAR         : natural := 0;
  constant BYTES_IN     : natural := IN_WIDTH / 8;
  constant BYTES_OUT    : natural := OUT_WIDTH / 8;
  constant BUFFER_WIDTH : natural := BUFFER_BYTES * 8;
  constant HEADER_LEN   : natural := 25;

  type fsm_t is (IDLE, HEADER, DATA);
  signal sFsmState : fsm_t := IDLE;

  signal sBuffer        : std_logic_vector(BUFFER_WIDTH - 1 downto 0) := (others => '0');
  signal sByteCount     : natural range 0 to BUFFER_BYTES             := 0;
  signal sEndOfImage    : natural range 0 to BUFFER_BYTES             := 0;
  signal sHasEndOfImage : std_logic                                   := '0';

  signal sOutWord    : std_logic_vector(OUT_WIDTH - 1 downto 0)           := (others => '0');
  signal sOutValid   : std_logic                                          := '0';
  signal sOutLast    : std_logic                                          := '0';
  signal sValidBytes : unsigned(log2ceil(OUT_WIDTH / 8 + 1) - 1 downto 0) := (others => '0');

  signal sHeaderByteIdx : natural range 0 to HEADER_LEN := 0;
  signal sNextPending   : std_logic                     := '0';

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
  assert BUFFER_BYTES >= BYTES_OUT + BYTES_IN + 2
  report "jls_framer: BUFFER_BYTES too small for one-cycle worst-case push (iBsValidBytes + footer)"
    severity failure;

  sAxiHandshake <= (iReady and sOutValid) = '1';

  oWord       <= sOutWord;
  oWordValid  <= sOutValid;
  oValidBytes <= sValidBytes;
  oLast       <= sOutLast;

  -- Advisory only: byte_stuffer cannot stall. With proper buffer sizing this
  -- always holds; deasserts as a defensive flag if buffer is near-full.
  oBsReady <= '1' when sByteCount + BYTES_IN + 2 <= BUFFER_BYTES else
    '0';

  process (iClk)
    variable vBuf           : std_logic_vector(BUFFER_WIDTH - 1 downto 0);
    variable vCount         : natural range 0 to BUFFER_BYTES;
    variable vEndOfImage    : natural range 0 to BUFFER_BYTES;
    variable vHasEndOfImage : std_logic;
    variable vWidth         : unsigned(15 downto 0);
    variable vHeight        : unsigned(15 downto 0);
    variable vHeaderRemain  : natural range 0 to HEADER_LEN;
    variable vDataNeeded    : natural range 0 to BYTES_OUT;
    variable vEmitData      : natural range 0 to BYTES_OUT;
    variable vEmitBytes     : natural range 0 to BYTES_OUT;
    variable vCanEmit       : boolean;
    variable vEoiInBeat     : boolean;
  begin
    if rising_edge(iClk) then
      if iRst = '1' then
        sFsmState      <= IDLE;
        sBuffer        <= (others => '0');
        sByteCount     <= 0;
        sEndOfImage    <= 0;
        sHasEndOfImage <= '0';
        sOutWord       <= (others => '0');
        sOutValid      <= '0';
        sOutLast       <= '0';
        sValidBytes    <= (others => '0');
        sHeaderByteIdx <= 0;
        sNextPending   <= '0';
      else

        vBuf           := sBuffer;
        vCount         := sByteCount;
        vEndOfImage    := sEndOfImage;
        vHasEndOfImage := sHasEndOfImage;
        vWidth         := resize(iImageWidth, 16);
        vHeight        := resize(iImageHeight, 16);
        vCanEmit       := sAxiHandshake or sOutValid = '0';

        ------------------------------------------------------------------------
        -- iStart latching (skipped if state=IDLE; IDLE handles iStart inline)
        ------------------------------------------------------------------------
        if iStart = '1' and sFsmState /= IDLE then
          sNextPending <= '1';
        end if;

        ------------------------------------------------------------------------
        -- POP: produce the next output beat. Runs before PUSH so the push
        -- section sees post-pop vCount/vEndOfImage and can place new bytes
        -- (and the footer) at the correct offset.
        ------------------------------------------------------------------------
        -- "Beat was consumed" guard: clear valid/last only after AXI handshake.
        -- Holds the beat under backpressure (iReady='0'); emit paths below
        -- override these when a new beat is produced.
        if sAxiHandshake then
          sOutValid <= '0';
          sOutLast  <= '0';
        end if;

        case sFsmState is

          when IDLE =>
            if iStart = '1' or sNextPending = '1' then
              sFsmState      <= HEADER;
              sHeaderByteIdx <= 0;
              sNextPending   <= '0';
            end if;

          when HEADER =>
            if vCanEmit then
              vHeaderRemain := HEADER_LEN - sHeaderByteIdx;

              if vHeaderRemain >= BYTES_OUT then
                -- Full header beat from ROM
                for i in 0 to BYTES_OUT - 1 loop
                  sOutWord(OUT_WIDTH - 1 - i * 8 downto OUT_WIDTH - (i + 1) * 8)
                  <= get_header_byte(sHeaderByteIdx + i, vWidth, vHeight);
                end loop;
                sValidBytes <= to_unsigned(BYTES_OUT, sValidBytes'length);
                sOutValid   <= '1';
                sOutLast    <= '0';
                if sHeaderByteIdx + BYTES_OUT = HEADER_LEN then
                  sFsmState <= DATA;
                else
                  sHeaderByteIdx <= sHeaderByteIdx + BYTES_OUT;
                end if;
              else
                -- Last header beat: fill remaining lanes from the FIFO
                vDataNeeded := BYTES_OUT - vHeaderRemain;
                vEoiInBeat  := vHasEndOfImage = '1' and vEndOfImage < vDataNeeded;
                if vEoiInBeat then
                  vEmitData := vEndOfImage + 1;
                else
                  vEmitData := vDataNeeded;
                end if;

                if vCount >= vEmitData then
                  for i in 0 to BYTES_OUT - 1 loop
                    if i < vHeaderRemain then
                      sOutWord(OUT_WIDTH - 1 - i * 8 downto OUT_WIDTH - (i + 1) * 8)
                      <= get_header_byte(sHeaderByteIdx + i, vWidth, vHeight);
                    elsif i < vHeaderRemain + vEmitData then
                      sOutWord(OUT_WIDTH - 1 - i * 8 downto OUT_WIDTH - (i + 1) * 8)
                      <= vBuf(BUFFER_WIDTH - 1 - (i - vHeaderRemain) * 8 downto
                      BUFFER_WIDTH - (i - vHeaderRemain + 1) * 8);
                    else
                      sOutWord(OUT_WIDTH - 1 - i * 8 downto OUT_WIDTH - (i + 1) * 8)
                      <= (others => '0');
                    end if;
                  end loop;
                  sValidBytes <= to_unsigned(vHeaderRemain + vEmitData, sValidBytes'length);
                  sOutValid   <= '1';
                  vBuf   := std_logic_vector(shift_left(unsigned(vBuf), vEmitData * 8));
                  vCount := vCount - vEmitData;

                  if vEoiInBeat then
                    sOutLast <= '1';
                    vHasEndOfImage := '0';
                    if sNextPending = '1' or iStart = '1' then
                      sFsmState      <= HEADER;
                      sHeaderByteIdx <= 0;
                      sNextPending   <= '0';
                    else
                      sFsmState <= IDLE;
                    end if;
                  else
                    sOutLast <= '0';
                    if vHasEndOfImage = '1' then
                      vEndOfImage := vEndOfImage - vDataNeeded;
                    end if;
                    sFsmState <= DATA;
                  end if;
                end if;
                -- else: stall (waiting for FIFO to fill)
              end if;
            end if;

          when DATA =>
            if vCanEmit then
              vEoiInBeat := vHasEndOfImage = '1' and vEndOfImage < BYTES_OUT;
              if vEoiInBeat then
                vEmitBytes := vEndOfImage + 1;
              else
                vEmitBytes := BYTES_OUT;
              end if;

              if vCount >= vEmitBytes then
                for i in 0 to BYTES_OUT - 1 loop
                  if i < vEmitBytes then
                    sOutWord(OUT_WIDTH - 1 - i * 8 downto OUT_WIDTH - (i + 1) * 8)
                    <= vBuf(BUFFER_WIDTH - 1 - i * 8 downto BUFFER_WIDTH - (i + 1) * 8);
                  else
                    sOutWord(OUT_WIDTH - 1 - i * 8 downto OUT_WIDTH - (i + 1) * 8)
                    <= (others => '0');
                  end if;
                end loop;
                sValidBytes <= to_unsigned(vEmitBytes, sValidBytes'length);
                sOutValid   <= '1';
                vBuf   := std_logic_vector(shift_left(unsigned(vBuf), vEmitBytes * 8));
                vCount := vCount - vEmitBytes;

                if vEoiInBeat then
                  sOutLast <= '1';
                  vHasEndOfImage := '0';
                  if sNextPending = '1' or iStart = '1' then
                    sFsmState      <= HEADER;
                    sHeaderByteIdx <= 0;
                    sNextPending   <= '0';
                  else
                    sFsmState <= IDLE;
                  end if;
                else
                  sOutLast <= '0';
                  if vHasEndOfImage = '1' then
                    vEndOfImage := vEndOfImage - BYTES_OUT;
                  end if;
                end if;
              end if;
              -- else: stall (FIFO underrun)
            end if;

        end case;

        ------------------------------------------------------------------------
        -- PUSH: byte_stuffer payload, then footer (on iEOI) at write pointer.
        -- Two sequential variable writes; synthesis collapses to a wide
        -- combinational update of vBuf.
        ------------------------------------------------------------------------
        if iBsWordValid = '1' then
          for i in 0 to BYTES_IN - 1 loop
            if i < to_integer(iBsValidBytes) then
              vBuf(BUFFER_WIDTH - 1 - (vCount + i) * 8 downto
              BUFFER_WIDTH - (vCount + i + 1) * 8)
              := iBsWord(IN_WIDTH - 1 - i * 8 downto IN_WIDTH - (i + 1) * 8);
            end if;
          end loop;
          vCount := vCount + to_integer(iBsValidBytes);
        end if;

        if iEOI = '1' then
          vBuf(BUFFER_WIDTH - 1 - vCount * 8 downto
          BUFFER_WIDTH - (vCount + 1) * 8) := x"FF";
          vBuf(BUFFER_WIDTH - 1 - (vCount + 1) * 8 downto
          BUFFER_WIDTH - (vCount + 2) * 8) := x"D9";
          vCount                           := vCount + 2;
          vEndOfImage                      := vCount - 1;
          vHasEndOfImage                   := '1';
        end if;

        sBuffer        <= vBuf;
        sByteCount     <= vCount;
        sEndOfImage    <= vEndOfImage;
        sHasEndOfImage <= vHasEndOfImage;

      end if;
    end if;
  end process;

end Behavioral;
