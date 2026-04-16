----------------------------------------------------------------------------------
-- Engineer:    Vitor Mendes Camilo
--
-- Module Name: openjls_top - rtl
-- Description: JPEG-LS T.87 lossless encoder top level
--              5-stage pipeline + input/output stages
--
-- TODO:
--   - Speculative three-chain for A.6-A.9 (currently single chain)
--   - Back-pressure from output stages to input
--   - Verify flush timing after EOI
----------------------------------------------------------------------------------
use work.Common.all;

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

library openlogic_base;
use openlogic_base.olo_base_pkg_math.log2ceil;

entity openjls_top is
  generic (
    BITNESS          : natural range 8 to 16 := CO_BITNESS_STD;
    MAX_IMAGE_WIDTH  : positive              := 4096;
    MAX_IMAGE_HEIGHT : positive              := 4096;
    OUT_WIDTH        : natural               := CO_OUT_WIDTH_STD
  );
  port (
    iClk         : in std_logic;
    iRst         : in std_logic;
    iValid       : in std_logic;
    iPixel       : in unsigned(BITNESS - 1 downto 0);
    oReady       : out std_logic;
    iImageWidth  : in unsigned(log2ceil(MAX_IMAGE_WIDTH + 1) - 1 downto 0);
    iImageHeight : in unsigned(log2ceil(MAX_IMAGE_HEIGHT + 1) - 1 downto 0);
    oData        : out std_logic_vector(OUT_WIDTH - 1 downto 0);
    oValid       : out std_logic;
    oKeep        : out unsigned(log2ceil(OUT_WIDTH / 8) downto 0);
    oLast        : out std_logic;
    iReady       : in std_logic
  );
end openjls_top;

architecture rtl of openjls_top is

  -- Derived constants
  constant MAX_VAL : natural := 2 ** BITNESS - 1;
  constant A_INIT  : natural := math_max(2, (MAX_VAL + 1 + 32) / 64);

  -- Context memory packing: Aq|Bq|Cq|Nq|Nn
  constant CTX_W   : natural := CO_AQ_WIDTH_STD + CO_BQ_WIDTH_STD + CO_CQ_WIDTH
                                + CO_NQ_WIDTH_STD + CO_NQ_WIDTH_STD;
  constant CTX_D   : natural := 512;
  constant CTX_AW  : natural := log2ceil(CTX_D);
  constant AQ_HI   : natural := CTX_W - 1;
  constant AQ_LO   : natural := CTX_W - CO_AQ_WIDTH_STD;
  constant BQ_HI   : natural := AQ_LO - 1;
  constant BQ_LO   : natural := AQ_LO - CO_BQ_WIDTH_STD;
  constant CQ_HI   : natural := BQ_LO - 1;
  constant CQ_LO   : natural := BQ_LO - CO_CQ_WIDTH;
  constant NQ_HI   : natural := CQ_LO - 1;
  constant NQ_LO   : natural := CQ_LO - CO_NQ_WIDTH_STD;
  constant NN_HI   : natural := NQ_LO - 1;
  constant NN_LO   : natural := 0;

  constant CTX_INIT : std_logic_vector(CTX_W - 1 downto 0) :=
    std_logic_vector(to_unsigned(A_INIT, CO_AQ_WIDTH_STD))
    & std_logic_vector(to_signed(0, CO_BQ_WIDTH_STD))
    & std_logic_vector(to_signed(0, CO_CQ_WIDTH))
    & std_logic_vector(to_unsigned(1, CO_NQ_WIDTH_STD))
    & std_logic_vector(to_unsigned(0, CO_NQ_WIDTH_STD));

  -- ═══════════════════════════════════════════════════════════════════
  -- Init FSM
  -- ═══════════════════════════════════════════════════════════════════
  type init_t is (INIT_WRITE, INIT_DONE);
  signal sInitState : init_t                              := INIT_WRITE;
  signal sInitAddr  : unsigned(CTX_AW - 1 downto 0)      := (others => '0');
  signal sInitDone  : std_logic;

  -- ═══════════════════════════════════════════════════════════════════
  -- Pipeline registers + sideband
  -- ═══════════════════════════════════════════════════════════════════
  signal sReg1, sReg2, sReg3, sReg4 : t_pipeline_token := CO_TOKEN_NONE;
  signal sReg1V, sReg2V, sReg3V, sReg4V : std_logic    := '0';
  signal sReg1EOL, sReg2EOL, sReg3EOL   : std_logic    := '0';
  signal sReg1EOI, sReg2EOI, sReg3EOI, sReg4EOI : std_logic := '0';
  signal sReg1ModeRun : std_logic := '0';

  -- ═══════════════════════════════════════════════════════════════════
  -- Input Stage — line buffer
  -- ═══════════════════════════════════════════════════════════════════
  signal sLbRa, sLbRb, sLbRc, sLbRd : unsigned(BITNESS - 1 downto 0);
  signal sLbValid, sLbEOL, sLbEOI   : std_logic;
  signal sLbIValid                   : std_logic;

  -- ═══════════════════════════════════════════════════════════════════
  -- Stage 1 — A.1 gradient + A.3 mode
  -- ═══════════════════════════════════════════════════════════════════
  signal sS1D1, sS1D2, sS1D3    : signed(BITNESS downto 0);
  signal sS1ModeRun, sS1ModeReg : std_logic;

  -- ═══════════════════════════════════════════════════════════════════
  -- Stage 2 — regular path
  -- ═══════════════════════════════════════════════════════════════════
  signal sS2Q1, sS2Q2, sS2Q3    : signed(3 downto 0);
  signal sS2MQ1, sS2MQ2, sS2MQ3 : signed(3 downto 0);
  signal sS2MSign                : std_logic;
  signal sS2QReg                 : unsigned(8 downto 0);

  -- Stage 2 — run path
  signal sRunCntReg     : unsigned(15 downto 0) := (others => '0');
  signal sS2RunCnt      : unsigned(15 downto 0);
  signal sS2RunRx       : unsigned(BITNESS - 1 downto 0);
  signal sS2RunHit      : std_logic;
  signal sS2RunContinue : std_logic;
  signal sS2RItype      : std_logic;
  signal sS2RawValid    : std_logic;
  signal sS2RawLen      : unsigned(4 downto 0);
  signal sS2RawVal      : unsigned(15 downto 0);
  signal sS2RIValid     : std_logic;
  signal sS2RIRunIdx    : unsigned(4 downto 0);
  signal sS2RIIx        : unsigned(BITNESS - 1 downto 0);
  signal sS2RIRa        : unsigned(BITNESS - 1 downto 0);
  signal sS2RIRb        : unsigned(BITNESS - 1 downto 0);

  -- Stage 2 — muxed outputs
  signal sS2Q         : unsigned(8 downto 0);
  signal sS2TokenMode : t_token_mode;

  -- ═══════════════════════════════════════════════════════════════════
  -- Context memory
  -- ═══════════════════════════════════════════════════════════════════
  signal sCtxRdAddr : std_logic_vector(CTX_AW - 1 downto 0);
  signal sCtxRdEn   : std_logic;
  signal sCtxRdData : std_logic_vector(CTX_W - 1 downto 0);
  signal sCtxWrAddr : std_logic_vector(CTX_AW - 1 downto 0);
  signal sCtxWrEn   : std_logic;
  signal sCtxWrData : std_logic_vector(CTX_W - 1 downto 0);

  -- Q3=Q4 forwarding
  signal sFwdHit  : std_logic;
  signal sCtxMux  : std_logic_vector(CTX_W - 1 downto 0);

  -- Dedicated run-interruption context registers (365, 366)
  signal sCtx365Aq : unsigned(CO_AQ_WIDTH_STD - 1 downto 0) := to_unsigned(A_INIT, CO_AQ_WIDTH_STD);
  signal sCtx365Nq : unsigned(CO_NQ_WIDTH_STD - 1 downto 0) := to_unsigned(1, CO_NQ_WIDTH_STD);
  signal sCtx365Nn : unsigned(CO_NQ_WIDTH_STD - 1 downto 0) := (others => '0');
  signal sCtx366Aq : unsigned(CO_AQ_WIDTH_STD - 1 downto 0) := to_unsigned(A_INIT, CO_AQ_WIDTH_STD);
  signal sCtx366Nq : unsigned(CO_NQ_WIDTH_STD - 1 downto 0) := to_unsigned(1, CO_NQ_WIDTH_STD);
  signal sCtx366Nn : unsigned(CO_NQ_WIDTH_STD - 1 downto 0) := (others => '0');

  -- A.20 forwarded inputs
  signal sA20_A365 : unsigned(CO_AQ_WIDTH_STD - 1 downto 0);
  signal sA20_A366 : unsigned(CO_AQ_WIDTH_STD - 1 downto 0);
  signal sA20_N366 : unsigned(CO_NQ_WIDTH_STD - 1 downto 0);

  -- ═══════════════════════════════════════════════════════════════════
  -- Stage 3 — regular prediction chain
  -- ═══════════════════════════════════════════════════════════════════
  signal sS3Px      : unsigned(BITNESS - 1 downto 0);
  signal sS3PxCorr  : unsigned(BITNESS - 1 downto 0);
  signal sS3Err7    : signed(BITNESS downto 0);
  signal sS3Err8    : signed(BITNESS downto 0);
  signal sS3Rx8     : unsigned(BITNESS - 1 downto 0);
  signal sS3Err9    : signed(BITNESS downto 0);

  -- Stage 3 — run-interruption path
  signal sS3RiPx    : unsigned(BITNESS - 1 downto 0);
  signal sS3RiErr18 : signed(BITNESS downto 0);
  signal sS3RiErr19 : signed(BITNESS downto 0);
  signal sS3RiRx    : unsigned(BITNESS - 1 downto 0);
  signal sS3RiSign  : std_logic;
  signal sS3RiTemp  : unsigned(CO_AQ_WIDTH_STD - 1 downto 0);
  signal sS3RiK     : unsigned(CO_K_WIDTH_STD - 1 downto 0);

  -- Stage 3 — context data (from BRAM or forwarded)
  signal sS3Aq : unsigned(CO_AQ_WIDTH_STD - 1 downto 0);
  signal sS3Bq : signed(CO_BQ_WIDTH_STD - 1 downto 0);
  signal sS3Cq : signed(CO_CQ_WIDTH - 1 downto 0);
  signal sS3Nq : unsigned(CO_NQ_WIDTH_STD - 1 downto 0);
  signal sS3Nn : unsigned(CO_NQ_WIDTH_STD - 1 downto 0);

  -- ═══════════════════════════════════════════════════════════════════
  -- Stage 4 — regular: A.10 + A.12 + A.13
  -- ═══════════════════════════════════════════════════════════════════
  signal sS4K       : unsigned(CO_K_WIDTH_STD - 1 downto 0);
  signal sS4AqNew   : unsigned(CO_AQ_WIDTH_STD - 1 downto 0);
  signal sS4BqMid   : signed(CO_BQ_WIDTH_STD - 1 downto 0);
  signal sS4NqNew   : unsigned(CO_NQ_WIDTH_STD - 1 downto 0);
  signal sS4BqNew   : signed(CO_BQ_WIDTH_STD - 1 downto 0);
  signal sS4CqNew   : signed(CO_CQ_WIDTH - 1 downto 0);

  -- Stage 4 — run-interruption: A.23
  signal sS4RiAqNew : unsigned(CO_AQ_WIDTH_STD - 1 downto 0);
  signal sS4RiNqNew : unsigned(CO_NQ_WIDTH_STD - 1 downto 0);
  signal sS4RiNnNew : unsigned(CO_NQ_WIDTH_STD - 1 downto 0);

  -- Stage 4 — context write word
  signal sS4CtxWord : std_logic_vector(CTX_W - 1 downto 0);

  -- ═══════════════════════════════════════════════════════════════════
  -- Stage 5 — regular: A.11; run: A.21 + A.22; shared: A.11.1
  -- ═══════════════════════════════════════════════════════════════════
  signal sS5MErrval    : unsigned(CO_MAPPED_ERROR_VAL_WIDTH_STD - 1 downto 0);
  signal sS5RiMap      : std_logic;
  signal sS5RiEMErrval : unsigned(CO_MAPPED_ERROR_VAL_WIDTH_STD - 1 downto 0);
  signal sS5GolK       : unsigned(CO_K_WIDTH_STD - 1 downto 0);
  signal sS5GolMErr    : unsigned(CO_MAPPED_ERROR_VAL_WIDTH_STD - 1 downto 0);
  signal sS5Unary      : unsigned(CO_UNARY_WIDTH_STD - 1 downto 0);
  signal sS5SufLen     : unsigned(CO_SUFFIXLEN_WIDTH_STD - 1 downto 0);
  signal sS5SufVal     : unsigned(CO_SUFFIX_WIDTH_STD - 1 downto 0);
  signal sS5TotLen     : unsigned(CO_TOTLEN_WIDTH_STD - 1 downto 0);
  signal sS5Escape     : std_logic;

  -- ═══════════════════════════════════════════════════════════════════
  -- Output stages
  -- ═══════════════════════════════════════════════════════════════════
  signal sBpRawV, sBpGolV : std_logic;
  signal sBpWord      : std_logic_vector(CO_BYTE_STUFFER_IN_WIDTH - 1 downto 0);
  signal sBpWordV     : std_logic;
  signal sBpOverflow  : std_logic;
  signal sBsReady     : std_logic;
  signal sBsWord      : std_logic_vector(CO_BYTE_STUFFER_IN_WIDTH - 1 downto 0);
  signal sBsWordV     : std_logic;
  signal sBsValidB    : unsigned(log2ceil(CO_BYTE_STUFFER_IN_WIDTH / 8) downto 0);
  signal sBsOReady    : std_logic;
  signal sFramerBsRdy : std_logic;

  -- Flush / control
  signal sEoiPipe      : std_logic_vector(4 downto 0) := (others => '0');
  signal sBpFlush      : std_logic;
  signal sBsFlush      : std_logic;
  signal sFramerEOI    : std_logic;
  signal sImageActive  : std_logic := '0';
  signal sFramerStart  : std_logic;

begin

  -- ═══════════════════════════════════════════════════════════════════
  -- Init FSM — writes initial context values to addresses 0..366
  -- ═══════════════════════════════════════════════════════════════════
  sInitDone <= '1' when sInitState = INIT_DONE else '0';
  oReady    <= sInitDone;

  process (iClk)
  begin
    if rising_edge(iClk) then
      if iRst = '1' then
        sInitState <= INIT_WRITE;
        sInitAddr  <= (others => '0');
      elsif sInitState = INIT_WRITE then
        if sInitAddr = 366 then
          sInitState <= INIT_DONE;
        else
          sInitAddr <= sInitAddr + 1;
        end if;
      end if;
    end if;
  end process;

  -- ═══════════════════════════════════════════════════════════════════
  -- Input Stage — line buffer
  -- ═══════════════════════════════════════════════════════════════════
  sLbIValid <= iValid and sInitDone;

  u_line_buffer : entity work.line_buffer
    generic map(
      MAX_IMAGE_WIDTH  => MAX_IMAGE_WIDTH,
      MAX_IMAGE_HEIGHT => MAX_IMAGE_HEIGHT,
      BITNESS          => BITNESS
    )
    port map(
      iClk         => iClk,
      iRst         => iRst,
      iImageWidth  => iImageWidth,
      iImageHeight => iImageHeight,
      iValid       => sLbIValid,
      iPixel       => iPixel,
      oA           => sLbRa,
      oB           => sLbRb,
      oC           => sLbRc,
      oD           => sLbRd,
      oValid       => sLbValid,
      oEOL         => sLbEOL,
      oEOI         => sLbEOI
    );

  -- ═══════════════════════════════════════════════════════════════════
  -- Stage 1 — A.1 gradient computation + A.3 mode selection (lossless)
  -- ═══════════════════════════════════════════════════════════════════
  u_a1 : entity work.A1_gradient_comp
    generic map(BITNESS => BITNESS)
    port map(
      iA => sLbRa, iB => sLbRb, iC => sLbRc, iD => sLbRd,
      oD1 => sS1D1, oD2 => sS1D2, oD3 => sS1D3
    );

  u_a3 : entity work.A3_mode_selection
    generic map(BITNESS => BITNESS)
    port map(
      iD1 => sS1D1, iD2 => sS1D2, iD3 => sS1D3,
      oModeRegular => sS1ModeReg, oModeRun => sS1ModeRun
    );

  -- ═══════════════════════════════════════════════════════════════════
  -- Register 1 (Stage 1 → Stage 2)
  -- ═══════════════════════════════════════════════════════════════════
  process (iClk)
    variable v : t_pipeline_token;
  begin
    if rising_edge(iClk) then
      if iRst = '1' then
        sReg1 <= CO_TOKEN_NONE; sReg1V <= '0';
        sReg1EOL <= '0'; sReg1EOI <= '0'; sReg1ModeRun <= '0';
      else
        v := CO_TOKEN_NONE;
        sReg1V <= '0'; sReg1EOL <= '0'; sReg1EOI <= '0'; sReg1ModeRun <= '0';
        if sLbValid = '1' then
          sReg1V       <= '1';
          sReg1EOL     <= sLbEOL;
          sReg1EOI     <= sLbEOI;
          sReg1ModeRun <= sS1ModeRun;
          v.Ix := resize(iPixel, CO_BITNESS_MAX_WIDTH);
          v.Ra := resize(sLbRa, CO_BITNESS_MAX_WIDTH);
          v.Rb := resize(sLbRb, CO_BITNESS_MAX_WIDTH);
          v.Rc := resize(sLbRc, CO_BITNESS_MAX_WIDTH);
          v.Rd := resize(sLbRd, CO_BITNESS_MAX_WIDTH);
          v.D1 := resize(sS1D1, CO_BITNESS_MAX_WIDTH + 1);
          v.D2 := resize(sS1D2, CO_BITNESS_MAX_WIDTH + 1);
          v.D3 := resize(sS1D3, CO_BITNESS_MAX_WIDTH + 1);
        end if;
        sReg1 <= v;
      end if;
    end if;
  end process;

  -- ═══════════════════════════════════════════════════════════════════
  -- Stage 2 — Regular path: A.4 → A.4.1 → A.4.2
  -- ═══════════════════════════════════════════════════════════════════
  u_a4 : entity work.A4_quantization_gradients
    generic map(BITNESS => BITNESS, MAX_VAL => MAX_VAL)
    port map(
      iD1 => sReg1.D1(BITNESS downto 0),
      iD2 => sReg1.D2(BITNESS downto 0),
      iD3 => sReg1.D3(BITNESS downto 0),
      oQ1 => sS2Q1, oQ2 => sS2Q2, oQ3 => sS2Q3
    );

  u_a4_1 : entity work.A4_1_quant_gradient_merging
    port map(
      iQ1 => sS2Q1, iQ2 => sS2Q2, iQ3 => sS2Q3,
      oQ1 => sS2MQ1, oQ2 => sS2MQ2, oQ3 => sS2MQ3,
      oSign => sS2MSign
    );

  u_a4_2 : entity work.A4_2_Q_mapping
    port map(
      iQ1 => sS2MQ1, iQ2 => sS2MQ2, iQ3 => sS2MQ3,
      oQ => sS2QReg
    );

  -- ═══════════════════════════════════════════════════════════════════
  -- Stage 2 — Run path: A.14 + A.15/A.16 FSM + A.17 + A.20.1 (inline)
  -- ═══════════════════════════════════════════════════════════════════
  u_a14 : entity work.A14_run_length_determination
    generic map(BITNESS => BITNESS)
    port map(
      iRa     => sReg1.Ra(BITNESS - 1 downto 0),
      iIx     => sReg1.Ix(BITNESS - 1 downto 0),
      iRunCnt => sRunCntReg,
      iEOL    => sReg1EOL,
      oRunCnt => sS2RunCnt, oRx => sS2RunRx,
      oRunHit => sS2RunHit, oRunContinue => sS2RunContinue
    );

  u_a15_16 : entity work.A15_A16_encode_run
    generic map(BITNESS => BITNESS)
    port map(
      iClk         => iClk,
      iRst         => iRst,
      iEOI         => sReg1EOI,
      iRunCnt      => sS2RunCnt,
      iRunHit      => sS2RunHit,
      iRunContinue => sS2RunContinue,
      iModeIsRun   => sReg1ModeRun,
      iIx          => sReg1.Ix(BITNESS - 1 downto 0),
      iRa          => sReg1.Ra(BITNESS - 1 downto 0),
      iRb          => sReg1.Rb(BITNESS - 1 downto 0),
      oRawValid    => sS2RawValid,
      oRawSuffixLen => sS2RawLen,
      oRawSuffixVal => sS2RawVal,
      oRIValid     => sS2RIValid,
      oRIRunIndex  => sS2RIRunIdx,
      oRIIx        => sS2RIIx,
      oRIRa        => sS2RIRa,
      oRIRb        => sS2RIRb
    );

  u_a17 : entity work.A17_run_interruption_index
    generic map(BITNESS => BITNESS)
    port map(
      iRa     => sReg1.Ra(BITNESS - 1 downto 0),
      iRb     => sReg1.Rb(BITNESS - 1 downto 0),
      oRItype => sS2RItype
    );

  -- Run counter register
  process (iClk)
  begin
    if rising_edge(iClk) then
      if iRst = '1' then
        sRunCntReg <= (others => '0');
      elsif sReg1V = '1' and sReg1ModeRun = '1' then
        if sS2RunContinue = '1' then
          sRunCntReg <= sS2RunCnt;
        else
          sRunCntReg <= (others => '0');
        end if;
      end if;
    end if;
  end process;

  -- Stage 2 mode + Q mux
  sS2TokenMode <=
    TOKEN_REGULAR          when sReg1ModeRun = '0' else
    TOKEN_RUN_INTERRUPTION when sS2RIValid = '1' else
    TOKEN_RAW              when sS2RawValid = '1' else
    TOKEN_NONE;

  -- A.20.1 (inline): Q = 366 if RItype else 365
  sS2Q <=
    sS2QReg                when sReg1ModeRun = '0' else
    to_unsigned(366, 9)    when sS2RItype = '1' else
    to_unsigned(365, 9);

  -- ═══════════════════════════════════════════════════════════════════
  -- Context memory
  -- ═══════════════════════════════════════════════════════════════════
  sCtxRdAddr <= std_logic_vector(resize(sS2Q, CTX_AW));
  sCtxRdEn   <= sReg1V;

  -- Write port: init FSM or Stage 4 writeback
  sCtxWrAddr <= std_logic_vector(resize(sInitAddr, CTX_AW)) when sInitDone = '0' else
    std_logic_vector(resize(sReg3.Q, CTX_AW));
  sCtxWrData <= CTX_INIT when sInitDone = '0' else
    sS4CtxWord;
  sCtxWrEn <= '1' when sInitDone = '0' else
    sReg3V and bool2bit(sReg3.mode = TOKEN_REGULAR or sReg3.mode = TOKEN_RUN_INTERRUPTION);

  u_ctx_ram : entity work.context_ram
    generic map(RAM_DEPTH => CTX_D, WORD_WIDTH => CTX_W)
    port map(
      iClk    => iClk,
      iWrAddr => sCtxWrAddr,
      iWrEn   => sCtxWrEn,
      iWrData => sCtxWrData,
      iRdAddr => sCtxRdAddr,
      iRdEn   => sCtxRdEn,
      oRdData => sCtxRdData
    );

  -- Q3=Q4 forwarding: Stage 3 pixel reads, Stage 4 pixel writes
  sFwdHit <= '1' when sReg2V = '1' and sReg3V = '1'
    and sReg2.Q = sReg3.Q
    and (sReg3.mode = TOKEN_REGULAR or sReg3.mode = TOKEN_RUN_INTERRUPTION)
    else '0';

  sCtxMux <= sS4CtxWord when sFwdHit = '1' else sCtxRdData;

  -- Unpack context data for Stage 3
  sS3Aq <= unsigned(sCtxMux(AQ_HI downto AQ_LO));
  sS3Bq <= signed(sCtxMux(BQ_HI downto BQ_LO));
  sS3Cq <= signed(sCtxMux(CQ_HI downto CQ_LO));
  sS3Nq <= unsigned(sCtxMux(NQ_HI downto NQ_LO));
  sS3Nn <= unsigned(sCtxMux(NN_HI downto NN_LO));

  -- Dedicated ctx 365/366 registers (for A.20)
  process (iClk)
  begin
    if rising_edge(iClk) then
      if iRst = '1' then
        sCtx365Aq <= to_unsigned(A_INIT, CO_AQ_WIDTH_STD);
        sCtx365Nq <= to_unsigned(1, CO_NQ_WIDTH_STD);
        sCtx365Nn <= (others => '0');
        sCtx366Aq <= to_unsigned(A_INIT, CO_AQ_WIDTH_STD);
        sCtx366Nq <= to_unsigned(1, CO_NQ_WIDTH_STD);
        sCtx366Nn <= (others => '0');
      elsif sReg3V = '1' and sReg3.mode = TOKEN_RUN_INTERRUPTION then
        if sReg3.Q = 365 then
          sCtx365Aq <= sS4RiAqNew;
          sCtx365Nq <= sS4RiNqNew;
          sCtx365Nn <= sS4RiNnNew;
        elsif sReg3.Q = 366 then
          sCtx366Aq <= sS4RiAqNew;
          sCtx366Nq <= sS4RiNqNew;
          sCtx366Nn <= sS4RiNnNew;
        end if;
      end if;
    end if;
  end process;

  -- Forwarding for A.20 inputs (Stage 4 may be updating ctx 365/366)
  sA20_A365 <= sS4RiAqNew when (sReg3V = '1' and sReg3.mode = TOKEN_RUN_INTERRUPTION and sReg3.Q = 365) else sCtx365Aq;
  sA20_A366 <= sS4RiAqNew when (sReg3V = '1' and sReg3.mode = TOKEN_RUN_INTERRUPTION and sReg3.Q = 366) else sCtx366Aq;
  sA20_N366 <= sS4RiNqNew when (sReg3V = '1' and sReg3.mode = TOKEN_RUN_INTERRUPTION and sReg3.Q = 366) else sCtx366Nq;

  -- ═══════════════════════════════════════════════════════════════════
  -- Register 2 (Stage 2 → Stage 3)
  -- ═══════════════════════════════════════════════════════════════════
  process (iClk)
    variable v : t_pipeline_token;
  begin
    if rising_edge(iClk) then
      if iRst = '1' then
        sReg2 <= CO_TOKEN_NONE; sReg2V <= '0';
        sReg2EOL <= '0'; sReg2EOI <= '0';
      else
        v         := sReg1;
        v.mode    := sS2TokenMode;
        v.Q       := sS2Q;
        v.Sign    := sS2MSign;
        v.RItype  := sS2RItype;
        v.RUNindex := resize(sS2RIRunIdx, v.RUNindex'length);
        v.RawSuffixLen := resize(sS2RawLen, v.RawSuffixLen'length);
        v.RawSuffixVal := resize(sS2RawVal, v.RawSuffixVal'length);
        if sReg1V = '0' then
          v := CO_TOKEN_NONE;
        end if;
        sReg2    <= v;
        sReg2V   <= sReg1V and bool2bit(sS2TokenMode /= TOKEN_NONE);
        sReg2EOL <= sReg1EOL;
        sReg2EOI <= sReg1EOI;
      end if;
    end if;
  end process;

  -- ═══════════════════════════════════════════════════════════════════
  -- Stage 3 — Regular: A.5 → A.6 → A.7 → A.8 → A.9
  -- TODO: speculative three-chain (C[Q], C[Q]+1, C[Q]-1) with mux
  -- ═══════════════════════════════════════════════════════════════════
  u_a5 : entity work.A5_edge_detecting_predictor
    generic map(BITNESS => BITNESS)
    port map(
      iA => sReg2.Ra(BITNESS - 1 downto 0),
      iB => sReg2.Rb(BITNESS - 1 downto 0),
      iC => sReg2.Rc(BITNESS - 1 downto 0),
      oPx => sS3Px
    );

  u_a6 : entity work.A6_prediction_correction
    generic map(BITNESS => BITNESS, MAX_VAL => MAX_VAL)
    port map(
      iPx   => sS3Px,
      iSign => sReg2.Sign,
      iCq   => sS3Cq,
      oPx   => sS3PxCorr
    );

  u_a7 : entity work.A7_prediction_error
    generic map(BITNESS => BITNESS)
    port map(
      iIx       => sReg2.Ix(BITNESS - 1 downto 0),
      iPx       => sS3PxCorr,
      iSign     => sReg2.Sign,
      oErrorVal => sS3Err7
    );

  u_a8 : entity work.A8_error_quantization
    generic map(BITNESS => BITNESS, MAX_VAL => MAX_VAL)
    port map(
      iErrorVal => sS3Err7,
      iPx       => sS3PxCorr,
      iSign     => sReg2.Sign,
      oErrorVal => sS3Err8,
      oRx       => sS3Rx8
    );

  u_a9 : entity work.A9_modulo_reduction
    generic map(BITNESS => BITNESS, MAX_VAL => MAX_VAL)
    port map(
      iErrorVal => sS3Err8,
      oErrorVal => sS3Err9
    );

  -- ═══════════════════════════════════════════════════════════════════
  -- Stage 3 — Run-interruption: A.18 → A.19, A.20, A.10 (k from TEMP)
  -- ═══════════════════════════════════════════════════════════════════
  u_a18 : entity work.A18_run_interruption_prediction_error
    generic map(BITNESS => BITNESS)
    port map(
      iRItype => sReg2.RItype,
      iRa     => sReg2.Ra(BITNESS - 1 downto 0),
      iRb     => sReg2.Rb(BITNESS - 1 downto 0),
      iIx     => sReg2.Ix(BITNESS - 1 downto 0),
      oPx     => sS3RiPx,
      oErrval => sS3RiErr18
    );

  u_a19 : entity work.A19_run_interruption_error
    generic map(BITNESS => BITNESS, MAX_VAL => MAX_VAL)
    port map(
      iErrval => sS3RiErr18,
      iPx     => sS3RiPx,
      iRItype => sReg2.RItype,
      iRa     => sReg2.Ra(BITNESS - 1 downto 0),
      iRb     => sReg2.Rb(BITNESS - 1 downto 0),
      iIx     => sReg2.Ix(BITNESS - 1 downto 0),
      oErrval => sS3RiErr19,
      oRx     => sS3RiRx,
      oSign   => sS3RiSign
    );

  u_a20 : entity work.A20_compute_temp
    port map(
      iRItype => sReg2.RItype,
      iA365   => sA20_A365,
      iA366   => sA20_A366,
      iN366   => sA20_N366,
      oTemp   => sS3RiTemp
    );

  u_a10_ri : entity work.A10_compute_k
    port map(
      iNq => sS3Nq,
      iAq => sS3RiTemp,
      oK  => sS3RiK
    );

  -- ═══════════════════════════════════════════════════════════════════
  -- Register 3 (Stage 3 → Stage 4) — mode mux for shared fields
  -- ═══════════════════════════════════════════════════════════════════
  process (iClk)
    variable v : t_pipeline_token;
  begin
    if rising_edge(iClk) then
      if iRst = '1' then
        sReg3 <= CO_TOKEN_NONE; sReg3V <= '0';
        sReg3EOL <= '0'; sReg3EOI <= '0';
      else
        v      := sReg2;
        v.Aq   := sS3Aq;
        v.Bq   := sS3Bq;
        v.Cq   := sS3Cq;
        v.Nq   := sS3Nq;
        v.Nn   := sS3Nn;
        case sReg2.mode is
          when TOKEN_REGULAR =>
            v.Px     := resize(sS3PxCorr, CO_BITNESS_MAX_WIDTH);
            v.Errval := resize(sS3Err9, CO_ERROR_VALUE_WIDTH_STD);
            v.Rx     := resize(sS3Rx8, CO_BITNESS_MAX_WIDTH);
          when TOKEN_RUN_INTERRUPTION =>
            v.Px     := resize(sS3RiPx, CO_BITNESS_MAX_WIDTH);
            v.Errval := resize(sS3RiErr19, CO_ERROR_VALUE_WIDTH_STD);
            v.Rx     := resize(sS3RiRx, CO_BITNESS_MAX_WIDTH);
            v.Sign   := sS3RiSign;
            v.k      := resize(sS3RiK, CO_K_WIDTH_STD);
          when others =>
            null;
        end case;
        if sReg2V = '0' then
          v := CO_TOKEN_NONE;
        end if;
        sReg3    <= v;
        sReg3V   <= sReg2V;
        sReg3EOL <= sReg2EOL;
        sReg3EOI <= sReg2EOI;
      end if;
    end if;
  end process;

  -- ═══════════════════════════════════════════════════════════════════
  -- Stage 4 — Regular: A.10 (k) + A.12 (update A,B,N) + A.13 (update B,C)
  -- ═══════════════════════════════════════════════════════════════════
  u_a10 : entity work.A10_compute_k
    port map(
      iNq => sReg3.Nq,
      iAq => sReg3.Aq,
      oK  => sS4K
    );

  u_a12 : entity work.A12_variables_update
    generic map(BITNESS => BITNESS)
    port map(
      iErrorVal => sReg3.Errval(BITNESS downto 0),
      iAq       => sReg3.Aq,
      iBq       => sReg3.Bq,
      iNq       => sReg3.Nq,
      oAq       => sS4AqNew,
      oBq       => sS4BqMid,
      oNq       => sS4NqNew
    );

  u_a13 : entity work.A13_update_bias
    port map(
      iBq => sS4BqMid,
      iNq => sS4NqNew,
      iCq => sReg3.Cq,
      oBq => sS4BqNew,
      oCq => sS4CqNew
    );

  -- ═══════════════════════════════════════════════════════════════════
  -- Stage 4 — Run-interruption: A.23
  -- ═══════════════════════════════════════════════════════════════════
  u_a23 : entity work.A23_run_interruption_update
    port map(
      iErrval => sReg3.Errval(BITNESS downto 0),
      iRItype => sReg3.RItype,
      iAq     => sReg3.Aq,
      iNq     => sReg3.Nq,
      iNn     => sReg3.Nn,
      oAq     => sS4RiAqNew,
      oNq     => sS4RiNqNew,
      oNn     => sS4RiNnNew
    );

  -- Context write word mux
  sS4CtxWord <=
    std_logic_vector(sS4AqNew) & std_logic_vector(sS4BqNew) & std_logic_vector(sS4CqNew)
      & std_logic_vector(sS4NqNew) & std_logic_vector(sReg3.Nn)
    when sReg3.mode = TOKEN_REGULAR else
    std_logic_vector(sS4RiAqNew) & std_logic_vector(sReg3.Bq) & std_logic_vector(sReg3.Cq)
      & std_logic_vector(sS4RiNqNew) & std_logic_vector(sS4RiNnNew);

  -- ═══════════════════════════════════════════════════════════════════
  -- Register 4 (Stage 4 → Stage 5)
  -- ═══════════════════════════════════════════════════════════════════
  process (iClk)
    variable v : t_pipeline_token;
  begin
    if rising_edge(iClk) then
      if iRst = '1' then
        sReg4 <= CO_TOKEN_NONE; sReg4V <= '0'; sReg4EOI <= '0';
      else
        v := sReg3;
        if sReg3.mode = TOKEN_REGULAR then
          v.k := resize(sS4K, CO_K_WIDTH_STD);
        end if;
        if sReg3V = '0' then
          v := CO_TOKEN_NONE;
        end if;
        sReg4    <= v;
        sReg4V   <= sReg3V;
        sReg4EOI <= sReg3EOI;
      end if;
    end if;
  end process;

  -- ═══════════════════════════════════════════════════════════════════
  -- Stage 5 — Regular: A.11 error mapping
  -- ═══════════════════════════════════════════════════════════════════
  u_a11 : entity work.A11_error_mapping
    port map(
      iK              => sReg4.k,
      iBq             => sReg4.Bq,
      iNq             => sReg4.Nq,
      iErrorVal       => sReg4.Errval,
      oMappedErrorVal => sS5MErrval
    );

  -- ═══════════════════════════════════════════════════════════════════
  -- Stage 5 — Run-interruption: A.21 map + A.22 error mapping
  -- ═══════════════════════════════════════════════════════════════════
  u_a21 : entity work.A21_compute_map
    port map(
      iK      => sReg4.k,
      iErrval => sReg4.Errval,
      iNn     => sReg4.Nn,
      iNq     => sReg4.Nq,
      oMap    => sS5RiMap
    );

  u_a22 : entity work.A22_errval_mapping
    port map(
      iErrval   => sReg4.Errval,
      iRItype   => sReg4.RItype,
      iMap      => sS5RiMap,
      oEMErrval => sS5RiEMErrval
    );

  -- Mode mux → Golomb encoder
  sS5GolK    <= sReg4.k;
  sS5GolMErr <= sS5MErrval when sReg4.mode = TOKEN_REGULAR else sS5RiEMErrval;

  u_a11_1 : entity work.A11_1_golomb_encoder
    port map(
      iK              => sS5GolK,
      iMappedErrorVal => sS5GolMErr,
      oUnaryZeros     => sS5Unary,
      oSuffixLen      => sS5SufLen,
      oSuffixVal      => sS5SufVal,
      oTotalLen       => sS5TotLen,
      oIsEscape       => sS5Escape
    );

  -- ═══════════════════════════════════════════════════════════════════
  -- Output stages — bit packer → byte stuffer → framer
  -- ═══════════════════════════════════════════════════════════════════

  -- Bit packer input valid signals
  sBpRawV <= '1' when sReg4V = '1'
    and (sReg4.mode = TOKEN_RAW or sReg4.mode = TOKEN_RUN_INTERRUPTION) else '0';
  sBpGolV <= '1' when sReg4V = '1'
    and (sReg4.mode = TOKEN_REGULAR or sReg4.mode = TOKEN_RUN_INTERRUPTION) else '0';

  u_bit_packer : entity work.A11_2_bit_packer
    port map(
      iClk         => iClk,
      iRst         => iRst,
      iFlush       => sBpFlush,
      iRawValid    => sBpRawV,
      iRawLen      => sReg4.RawSuffixLen,
      iRawVal      => sReg4.RawSuffixVal,
      iGolombValid => sBpGolV,
      iUnaryZeros  => sS5Unary,
      iSuffixLen   => sS5SufLen,
      iSuffixVal   => sS5SufVal,
      iReady       => sBsReady,
      oWord        => sBpWord,
      oWordValid   => sBpWordV,
      oBufferOverflow => sBpOverflow
    );

  u_byte_stuffer : entity work.byte_stuffer
    port map(
      iClk        => iClk,
      iRst        => iRst,
      iValid      => sBpWordV,
      iWord       => sBpWord,
      iFlush      => sBsFlush,
      oReady      => sBsReady,
      oWord       => sBsWord,
      oWordValid  => sBsWordV,
      oValidBytes => sBsValidB,
      iReady      => sFramerBsRdy
    );

  u_framer : entity work.jls_framer
    generic map(
      BITNESS   => BITNESS,
      OUT_WIDTH => OUT_WIDTH,
      MAX_IMAGE_WIDTH  => MAX_IMAGE_WIDTH,
      MAX_IMAGE_HEIGHT => MAX_IMAGE_HEIGHT
    )
    port map(
      iClk         => iClk,
      iRst         => iRst,
      iStart       => sFramerStart,
      iImageWidth  => iImageWidth,
      iImageHeight => iImageHeight,
      iEOI         => sFramerEOI,
      iBsWord      => sBsWord,
      iBsWordValid => sBsWordV,
      iBsValidBytes => sBsValidB,
      oBsReady     => sFramerBsRdy,
      oWord        => oData,
      oWordValid   => oValid,
      oValidBytes  => oKeep,
      oLast        => oLast,
      iReady       => iReady
    );

  -- ═══════════════════════════════════════════════════════════════════
  -- Flush / framer control
  -- ═══════════════════════════════════════════════════════════════════

  -- EOI delay chain: sReg4EOI propagates to flush signals
  -- Bit packer registers inputs (2 cycles), byte stuffer registers (1 cycle)
  process (iClk)
  begin
    if rising_edge(iClk) then
      if iRst = '1' then
        sEoiPipe <= (others => '0');
      else
        sEoiPipe <= sEoiPipe(3 downto 0) & sReg4EOI;
      end if;
    end if;
  end process;

  sBpFlush   <= sEoiPipe(1);
  sBsFlush   <= sEoiPipe(2);
  sFramerEOI <= sEoiPipe(3);

  -- Framer start: pulse on first valid pixel of each image
  process (iClk)
  begin
    if rising_edge(iClk) then
      if iRst = '1' then
        sImageActive <= '0';
      else
        if sInitDone = '1' and sLbIValid = '1' and sImageActive = '0' then
          sImageActive <= '1';
        elsif sEoiPipe(4) = '1' then
          sImageActive <= '0';
        end if;
      end if;
    end if;
  end process;

  sFramerStart <= sInitDone and sLbIValid and not sImageActive;

end rtl;
