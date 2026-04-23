----------------------------------------------------------------------------------
-- Engineer:    Vitor Mendes Camilo
--
-- Module Name: openjls_top - rtl
-- Description: JPEG-LS T.87 lossless encoder top level.
--              5-stage pipeline (Stage1..Stage5) + input/output stages.
--
--   Input Stage : line_buffer → {Ra, Rb, Rc, Rd, EOL, EOI}
--   Stage 1     : A.1 gradients + A.3 mode select
--     Reg1 ──►
--   Stage 2     : regular {A.4, A.4.1, A.4.2} | run {A.14, A.15/16, A.17}
--                 context_ram read starts here (address = sS2Q).
--     Reg2 ──►   (BRAM RdLatency=1 is the Stage 2→3 boundary for ctx bits)
--   Stage 3     : regular {A.5, speculative 3×{A.6..A.9}} | RI {A.18, A.19, A.20}
--                 context_ram delivers BRAM (Q<365) / cluster (365/366); internal
--                 1-deep writeback forwarding covers the Q3==Q4 hazard.
--     Reg3 ──►
--   Stage 4     : shared {A.10} | regular {A.12, A.13} | RI {A.23}; ctx writeback.
--     Reg4 ──►
--   Stage 5     : regular {A.11} | RI {A.21, A.22}; A.11.1 shared.
--   Output      : bit_packer (raw+Golomb concurrent) → byte_stuffer → jls_framer.
--
-- Speculative Cq chain: regular A.6..A.9 runs three times in parallel using
-- {Cq_base − 1, Cq_base, Cq_base + 1}, where Cq_base = sReg3.Cq on a
-- forwarding hit (Q at Stage 3 == Q at Stage 4, both regular) and the
-- context_ram-delivered sS3Cq otherwise. The chosen chain is selected late
-- by ΔCq = sS4CqNew − sReg3.Cq from live A.13, breaking the long
-- A.13 → A.6..A.9 combinational path.
--
-- Shared A.10 lives in Stage 4 and consumes sReg3.Aq (regular) or
-- sReg3.Temp (RI A.20 result carried through Reg3) via a 2:1 mux.
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
    iPixel       : in std_logic_vector(BITNESS - 1 downto 0);
    oReady       : out std_logic;
    iImageWidth  : in std_logic_vector(log2ceil(MAX_IMAGE_WIDTH + 1) - 1 downto 0);
    iImageHeight : in std_logic_vector(log2ceil(MAX_IMAGE_HEIGHT + 1) - 1 downto 0);
    oData        : out std_logic_vector(OUT_WIDTH - 1 downto 0);
    oValid       : out std_logic;
    oKeep        : out std_logic_vector(OUT_WIDTH / 8 - 1 downto 0);
    oLast        : out std_logic;
    iReady       : in std_logic
  );
end openjls_top;

architecture rtl of openjls_top is

  -- Derived constants
  constant MAX_VAL   : natural := 2 ** BITNESS - 1;
  constant CTX_RANGE : natural := MAX_VAL + 1;

  -- Packed context word slicing (A | B | C | N), matching context_ram layout.
  -- For RI contexts (Q=365,366) Nn overlays the LSBs of the B slot.
  constant CTX_A_HI  : natural := CO_TOTAL_WIDTH_STD - 1;
  constant CTX_A_LO  : natural := CO_TOTAL_WIDTH_STD - CO_AQ_WIDTH_STD;
  constant CTX_B_HI  : natural := CTX_A_LO - 1;
  constant CTX_B_LO  : natural := CTX_A_LO - CO_BQ_WIDTH_STD;
  constant CTX_C_HI  : natural := CTX_B_LO - 1;
  constant CTX_C_LO  : natural := CTX_B_LO - CO_CQ_WIDTH;
  constant CTX_N_HI  : natural := CTX_C_LO - 1;
  constant CTX_N_LO  : natural := 0;
  constant CTX_NN_HI : natural := CTX_B_LO + CO_NNQ_WIDTH_STD - 1;
  constant CTX_NN_LO : natural := CTX_B_LO;

  -- Ready flag: asserts one cycle after iRst deasserts. context_ram's bit-vector
  -- init makes the first read valid from the first post-reset cycle anyway.
  signal sReady : std_logic := '0';

  -- Pipeline tokens + sideband
  signal sReg1, sReg2, sReg3, sReg4             : t_pipeline_token         := CO_TOKEN_NONE;
  signal sReg1V, sReg2V, sReg3V, sReg4V         : std_logic                := '0';
  signal sReg1EOL                               : std_logic                := '0';
  signal sReg1EOI, sReg2EOI, sReg3EOI, sReg4EOI : std_logic                := '0';
  signal sReg1ModeRun                           : std_logic                := '0';
  signal sReg1D1, sReg1D2, sReg1D3              : signed(BITNESS downto 0) := (others => '0');

  -- Input stage
  signal sPixel                     : unsigned(BITNESS - 1 downto 0);
  signal sImageWidth                : unsigned(log2ceil(MAX_IMAGE_WIDTH + 1) - 1 downto 0);
  signal sImageHeight               : unsigned(log2ceil(MAX_IMAGE_HEIGHT + 1) - 1 downto 0);
  signal sValid                     : std_logic := '0'; -- iValid & sReady
  signal sLbRa, sLbRb, sLbRc, sLbRd : unsigned(BITNESS - 1 downto 0);
  signal sLbValid, sLbEOL, sLbEOI   : std_logic;

  -- Stage 1 combinational
  signal sS1D1, sS1D2, sS1D3 : signed(BITNESS downto 0);
  signal sS1ModeRun          : std_logic;

  -- Stage 2 — regular
  signal sS2Q1, sS2Q2, sS2Q3    : signed(3 downto 0);
  signal sS2MQ1, sS2MQ2, sS2MQ3 : signed(3 downto 0);
  signal sS2MSign               : std_logic;
  signal sS2QReg                : unsigned(8 downto 0);

  -- Stage 2 — run
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
  signal sS2RIIx        : unsigned(BITNESS - 1 downto 0);
  signal sS2RIRa        : unsigned(BITNESS - 1 downto 0);
  signal sS2RIRb        : unsigned(BITNESS - 1 downto 0);

  -- Stage 2 — muxed
  signal sS2Q         : unsigned(8 downto 0);
  signal sS2TokenMode : t_token_mode;

  -- context_ram packed I/O
  signal sCtxRdData : std_logic_vector(CO_TOTAL_WIDTH_STD - 1 downto 0);
  signal sCtxWrData : std_logic_vector(CO_TOTAL_WIDTH_STD - 1 downto 0);
  signal sCtxWrEn   : std_logic;

  -- Stage 3 context (mux between BRAM regular read and RI cluster read)
  signal sS3Aq : unsigned(CO_AQ_WIDTH_STD - 1 downto 0);
  signal sS3Bq : signed(CO_BQ_WIDTH_STD - 1 downto 0);
  signal sS3Cq : signed(CO_CQ_WIDTH - 1 downto 0);
  signal sS3Nq : unsigned(CO_NQ_WIDTH_STD - 1 downto 0);
  signal sS3Nn : unsigned(CO_NQ_WIDTH_STD - 1 downto 0);

  -- Stage 3 — regular prediction (speculative 3-chain)
  signal sS3Px                        : unsigned(BITNESS - 1 downto 0);
  signal sS3CqBase, sS3CqP1, sS3CqM1  : signed(CO_CQ_WIDTH - 1 downto 0);
  signal sS3PxC, sS3PxP, sS3PxM       : unsigned(BITNESS - 1 downto 0);
  signal sS3Err7C, sS3Err7P, sS3Err7M : signed(BITNESS downto 0);
  signal sS3Err8C, sS3Err8P, sS3Err8M : signed(BITNESS downto 0);
  signal sS3Err9C, sS3Err9P, sS3Err9M : signed(BITNESS downto 0);
  signal sS3Err9Sel                   : signed(BITNESS downto 0);

  -- Speculation control
  signal sFwdRegHit : std_logic;
  signal sDeltaCq   : signed(CO_CQ_WIDTH - 1 downto 0);
  signal sSpecUseM  : std_logic;
  signal sSpecUseP  : std_logic;

  -- Stage 3 — RI path
  signal sS3RiPx                : unsigned(BITNESS - 1 downto 0);
  signal sS3RiRx                : unsigned(BITNESS - 1 downto 0);
  signal sS3RiSign              : std_logic;
  signal sS3RiErr18, sS3RiErr19 : signed(BITNESS downto 0);
  signal sS3RiTemp              : unsigned(CO_AQ_WIDTH_STD - 1 downto 0);

  -- Stage 4
  signal sS4K       : unsigned(CO_K_WIDTH_STD - 1 downto 0);
  signal sS4AqSel   : unsigned(CO_AQ_WIDTH_STD - 1 downto 0); -- iAq mux for shared A.10
  signal sS4AqNew   : unsigned(CO_AQ_WIDTH_STD - 1 downto 0);
  signal sS4BqMid   : signed(CO_BQ_WIDTH_STD - 1 downto 0);
  signal sS4NqNew   : unsigned(CO_NQ_WIDTH_STD - 1 downto 0);
  signal sS4BqNew   : signed(CO_BQ_WIDTH_STD - 1 downto 0);
  signal sS4CqNew   : signed(CO_CQ_WIDTH - 1 downto 0);
  signal sS4RiAqNew : unsigned(CO_AQ_WIDTH_STD - 1 downto 0);
  signal sS4RiNqNew : unsigned(CO_NQ_WIDTH_STD - 1 downto 0);
  signal sS4RiNnNew : unsigned(CO_NQ_WIDTH_STD - 1 downto 0);

  -- Stage 5
  signal sS5MErrval    : unsigned(CO_MAPPED_ERROR_VAL_WIDTH_STD - 1 downto 0);
  signal sS5RiMap      : std_logic;
  signal sS5RiEMErrval : unsigned(CO_MAPPED_ERROR_VAL_WIDTH_STD - 1 downto 0);
  signal sS5GolMErr    : unsigned(CO_MAPPED_ERROR_VAL_WIDTH_STD - 1 downto 0);
  signal sS5Unary      : unsigned(CO_UNARY_WIDTH_STD - 1 downto 0);
  signal sS5SufLen     : unsigned(CO_SUFFIXLEN_WIDTH_STD - 1 downto 0);
  signal sS5SufVal     : unsigned(CO_SUFFIX_WIDTH_STD - 1 downto 0);

  -- Output
  signal sBpRawV, sBpGolV : std_logic;
  signal sBpWord          : std_logic_vector(CO_BYTE_STUFFER_IN_WIDTH - 1 downto 0);
  signal sBpWordV         : std_logic;
  signal sBpOverflow      : std_logic;
  signal sBsReady         : std_logic;
  signal sBsWord          : std_logic_vector(CO_BYTE_STUFFER_IN_WIDTH - 1 downto 0);
  signal sBsWordV         : std_logic;
  signal sBsValidB        : unsigned(log2ceil(CO_BYTE_STUFFER_IN_WIDTH / 8) downto 0);
  signal sFramerBsRdy     : std_logic;
  signal sFramerVBytes    : unsigned(log2ceil(OUT_WIDTH / 8) downto 0);

  -- Flush / framer control
  signal sEoiPipe     : std_logic_vector(4 downto 0) := (others => '0');
  signal sBpFlush     : std_logic;
  signal sBsFlush     : std_logic;
  signal sFramerEOI   : std_logic;
  signal sImageActive : std_logic := '0';
  signal sFramerStart : std_logic;

begin

  -- Ready: asserted one cycle after iRst deasserts.
  process (iClk)
  begin
    if rising_edge(iClk) then
      if iRst = '1' then
        sReady <= '0';
      else
        sReady <= '1';
      end if;
    end if;
  end process;

  oReady <= sReady;

  -- ═══════════════════════════════════════════════════════════════════
  -- Input Stage — Input register + line buffer
  -- ═══════════════════════════════════════════════════════════════════
  process (iClk)
  begin
    if rising_edge(iClk) then
      if iRst = '1' then
        sImageWidth  <= unsigned(iImageWidth);
        sImageHeight <= unsigned(iImageHeight);
        sValid       <= '0';
      elsif iValid = '1' and sReady = '1' then -- handshake
        sPixel <= unsigned(iPixel);
        sValid <= '1';
      else
        sValid <= '0';
      end if;
    end if;
  end process;

  u_line_buffer : entity work.line_buffer
    generic map(
      MAX_IMAGE_WIDTH  => MAX_IMAGE_WIDTH,
      MAX_IMAGE_HEIGHT => MAX_IMAGE_HEIGHT,
      BITNESS          => BITNESS
    )
    port map
    (
      iClk         => iClk,
      iRst         => iRst,
      iImageWidth  => sImageWidth,
      iImageHeight => sImageHeight,
      iValid       => sValid,
      iPixel       => sPixel,
      oA           => sLbRa,
      oB           => sLbRb,
      oC           => sLbRc,
      oD           => sLbRd,
      oValid       => sLbValid,
      oEOL         => sLbEOL,
      oEOI         => sLbEOI
    );

  -- ═══════════════════════════════════════════════════════════════════
  -- Stage 1 — A.1 gradients + A.3 mode selection
  -- ═══════════════════════════════════════════════════════════════════
  u_a1 : entity work.A1_gradient_comp
    generic map(BITNESS => BITNESS)
    port map
    (
      iA => sLbRa, iB => sLbRb, iC => sLbRc, iD => sLbRd,
      oD1 => sS1D1, oD2 => sS1D2, oD3 => sS1D3
    );

  u_a3 : entity work.A3_mode_selection
    generic map(BITNESS => BITNESS)
    port map
    (
      iD1 => sS1D1, iD2 => sS1D2, iD3 => sS1D3,
      oModeRun => sS1ModeRun
    );

  -- ═══════════════════════════════════════════════════════════════════
  -- Register 1 (Stage 1 → Stage 2)
  -- ═══════════════════════════════════════════════════════════════════
  process (iClk)
    variable v : t_pipeline_token;
  begin
    if rising_edge(iClk) then
      if iRst = '1' then
        sReg1        <= CO_TOKEN_NONE;
        sReg1V       <= '0';
        sReg1EOL     <= '0';
        sReg1EOI     <= '0';
        sReg1ModeRun <= '0';
        sReg1D1      <= (others => '0');
        sReg1D2      <= (others => '0');
        sReg1D3      <= (others => '0');
      else
        v := CO_TOKEN_NONE;
        if sLbValid = '1' then
          v.Ix := resize(sPixel, CO_BITNESS_MAX_WIDTH);
          v.Ra := resize(sLbRa, CO_BITNESS_MAX_WIDTH);
          v.Rb := resize(sLbRb, CO_BITNESS_MAX_WIDTH);
          v.Rc := resize(sLbRc, CO_BITNESS_MAX_WIDTH);
        end if;
        sReg1        <= v;
        sReg1V       <= sLbValid;
        sReg1EOL     <= sLbValid and sLbEOL;
        sReg1EOI     <= sLbValid and sLbEOI;
        sReg1ModeRun <= sLbValid and sS1ModeRun;
        sReg1D1      <= sS1D1;
        sReg1D2      <= sS1D2;
        sReg1D3      <= sS1D3;
      end if;
    end if;
  end process;

  -- ═══════════════════════════════════════════════════════════════════
  -- Stage 2 — Regular: A.4 → A.4.1 → A.4.2
  -- ═══════════════════════════════════════════════════════════════════
  u_a4 : entity work.A4_quantization_gradients
    generic map(BITNESS => BITNESS, MAX_VAL => MAX_VAL)
    port map
    (
      iD1 => sReg1D1, iD2 => sReg1D2, iD3 => sReg1D3,
      oQ1 => sS2Q1, oQ2 => sS2Q2, oQ3 => sS2Q3
    );

  u_a4_1 : entity work.A4_1_quant_gradient_merging
    port map
    (
      iQ1 => sS2Q1, iQ2 => sS2Q2, iQ3 => sS2Q3,
      oQ1 => sS2MQ1, oQ2 => sS2MQ2, oQ3 => sS2MQ3,
      oSign => sS2MSign
    );

  u_a4_2 : entity work.A4_2_Q_mapping
    port map
    (
      iQ1 => sS2MQ1, iQ2 => sS2MQ2, iQ3 => sS2MQ3,
      oQ => sS2QReg
    );

  -- ═══════════════════════════════════════════════════════════════════
  -- Stage 2 — Run: A.14, A.15/A.16 (FSM), A.17
  -- ═══════════════════════════════════════════════════════════════════
  u_a14 : entity work.A14_run_length_determination
    generic map(BITNESS => BITNESS)
    port map
    (
      iRa     => sReg1.Ra(BITNESS - 1 downto 0),
      iIx     => sReg1.Ix(BITNESS - 1 downto 0),
      iRunCnt => sRunCntReg,
      iEOL    => sReg1EOL,
      oRunCnt => sS2RunCnt, oRx => sS2RunRx,
      oRunHit => sS2RunHit, oRunContinue => sS2RunContinue
    );

  u_a15_16 : entity work.A15_A16_encode_run
    generic map(BITNESS => BITNESS)
    port map
    (
      iClk          => iClk,
      iRst          => iRst,
      iEOI          => sReg1EOI,
      iRunCnt       => sS2RunCnt,
      iRunHit       => sS2RunHit,
      iRunContinue  => sS2RunContinue,
      iModeIsRun    => sReg1ModeRun,
      iIx           => sReg1.Ix(BITNESS - 1 downto 0),
      iRa           => sReg1.Ra(BITNESS - 1 downto 0),
      iRb           => sReg1.Rb(BITNESS - 1 downto 0),
      oRawValid     => sS2RawValid,
      oRawSuffixLen => sS2RawLen,
      oRawSuffixVal => sS2RawVal,
      oRIValid      => sS2RIValid,
      oRIIx         => sS2RIIx,
      oRIRa         => sS2RIRa,
      oRIRb         => sS2RIRb
    );

  u_a17 : entity work.A17_run_interruption_index
    generic map(BITNESS => BITNESS)
    port map
    (
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

  -- Stage 2 mode selection. Precedence: RI break (Golomb+raw) > raw-only.
  sS2TokenMode <=
    TOKEN_REGULAR when sReg1ModeRun = '0' else
    TOKEN_RUN_INTERRUPTION when sS2RIValid = '1' else
    TOKEN_RAW when sS2RawValid = '1' else
    TOKEN_NONE;

  -- A.20.1 inline: regular Q from A.4.2; run Q = 366 if RItype else 365
  sS2Q <=
    sS2QReg when sReg1ModeRun = '0' else
    to_unsigned(366, 9) when sS2RItype = '1' else
    to_unsigned(365, 9);

  -- ═══════════════════════════════════════════════════════════════════
  -- Context store: single packed BRAM, Q = 0..366. Init via bit-vector
  -- flag inside context_ram (first-read-returns-init). For RI contexts
  -- (Q=365,366) Nn is packed into the LSBs of the B slot; C slot is
  -- unused for RI (written as zeros).
  -- ═══════════════════════════════════════════════════════════════════
  sCtxWrEn <= sReg3V and
    (bool2bit(sReg3.mode = TOKEN_REGULAR) or
    bool2bit(sReg3.mode = TOKEN_RUN_INTERRUPTION));

  -- Pack writeback word by mode.
  sCtxWrData <=
    std_logic_vector(sS4AqNew) &
    std_logic_vector(sS4BqNew) &
    std_logic_vector(sS4CqNew) &
    std_logic_vector(sS4NqNew)
    when sReg3.mode = TOKEN_REGULAR else
    std_logic_vector(sS4RiAqNew) &
    std_logic_vector(to_unsigned(0, CO_BQ_WIDTH_STD - CO_NNQ_WIDTH_STD)) &
    std_logic_vector(sS4RiNnNew) &
    std_logic_vector(to_signed(0, CO_CQ_WIDTH)) &
    std_logic_vector(sS4RiNqNew);

  u_ctx_ram : entity work.context_ram
    generic map(
      RANGE_P => CTX_RANGE
    )
    port map
    (
      iClk    => iClk,
      iRst    => iRst,
      iWrAddr => std_logic_vector(sReg3.Q),
      iWrEn   => sCtxWrEn,
      iWrData => sCtxWrData,
      iRdAddr => std_logic_vector(sS2Q),
      iRdEn   => sReg1V,
      oRdData => sCtxRdData
    );

  -- Unpack read port (BRAM RdLatency=1 → valid at Stage 3).
  sS3Aq <= unsigned(sCtxRdData(CTX_A_HI downto CTX_A_LO));
  sS3Bq <= signed(sCtxRdData(CTX_B_HI downto CTX_B_LO));
  sS3Cq <= signed(sCtxRdData(CTX_C_HI downto CTX_C_LO));
  sS3Nq <= unsigned(sCtxRdData(CTX_N_HI downto CTX_N_LO));

  -- Nn is only meaningful for RI; mask out for regular so downstream doesn't
  -- see Bq LSBs misinterpreted as Nn.
  sS3Nn <= (others => '0') when sReg2.mode = TOKEN_REGULAR
    else
    unsigned(sCtxRdData(CTX_NN_HI downto CTX_NN_LO));

  -- ═══════════════════════════════════════════════════════════════════
  -- Register 2 (Stage 2 → Stage 3)
  -- ═══════════════════════════════════════════════════════════════════
  process (iClk)
    variable v : t_pipeline_token;
  begin
    if rising_edge(iClk) then
      if iRst = '1' then
        sReg2    <= CO_TOKEN_NONE;
        sReg2V   <= '0';
        sReg2EOI <= '0';
      else
        v        := sReg1;
        v.mode   := sS2TokenMode;
        v.Q      := sS2Q;
        v.Sign   := sS2MSign;
        v.RItype := sS2RItype;
        v.RawLen := resize(sS2RawLen, v.RawLen'length);
        v.RawVal := resize(sS2RawVal, v.RawVal'length);
        if sS2TokenMode = TOKEN_RUN_INTERRUPTION then
          v.Ix := resize(sS2RIIx, CO_BITNESS_MAX_WIDTH);
          v.Ra := resize(sS2RIRa, CO_BITNESS_MAX_WIDTH);
          v.Rb := resize(sS2RIRb, CO_BITNESS_MAX_WIDTH);
        end if;
        if sReg1V = '0' or sS2TokenMode = TOKEN_NONE then
          v := CO_TOKEN_NONE;
        end if;
        sReg2    <= v;
        sReg2V   <= sReg1V and bool2bit(sS2TokenMode /= TOKEN_NONE);
        sReg2EOI <= sReg1EOI;
      end if;
    end if;
  end process;

  -- ═══════════════════════════════════════════════════════════════════
  -- Stage 3 — Regular: A.5 + speculative 3-chain A.6..A.9
  -- ═══════════════════════════════════════════════════════════════════
  u_a5 : entity work.A5_edge_detecting_predictor
    generic map(BITNESS => BITNESS)
    port map
    (
      iA  => sReg2.Ra(BITNESS - 1 downto 0),
      iB  => sReg2.Rb(BITNESS - 1 downto 0),
      iC  => sReg2.Rc(BITNESS - 1 downto 0),
      oPx => sS3Px
    );

  -- Forwarding hit: Stage 3 and Stage 4 share the same regular context Q.
  sFwdRegHit <= '1' when sReg2V = '1' and sReg3V = '1'
    and sReg2.Q = sReg3.Q
    and sReg2.mode = TOKEN_REGULAR
    and sReg3.mode = TOKEN_REGULAR
    else
    '0';

  -- Cq base: on hit use the register (sReg3.Cq) to stay off the A.13 path;
  -- otherwise the context_ram-delivered sS3Cq.
  sS3CqBase <= sReg3.Cq when sFwdRegHit = '1' else
    sS3Cq;

  -- Clamped ±1 variants
  sS3CqP1 <= to_signed(CO_MAX_CQ, CO_CQ_WIDTH) when sS3CqBase = to_signed(CO_MAX_CQ, CO_CQ_WIDTH)
    else
    sS3CqBase + 1;
  sS3CqM1 <= to_signed(CO_MIN_CQ, CO_CQ_WIDTH) when sS3CqBase = to_signed(CO_MIN_CQ, CO_CQ_WIDTH)
    else
    sS3CqBase - 1;

  -- Central chain (ΔCq = 0)
  u_a6_c : entity work.A6_prediction_correction
    generic map(BITNESS => BITNESS, MAX_VAL => MAX_VAL)
    port map
      (iPx => sS3Px, iSign => sReg2.Sign, iCq => sS3CqBase, oPx => sS3PxC);

  u_a7_c : entity work.A7_prediction_error
    generic map(BITNESS => BITNESS)
    port map
    (
      iIx => sReg2.Ix(BITNESS - 1 downto 0), iPx => sS3PxC,
      iSign => sReg2.Sign, oErrorVal => sS3Err7C);

  u_a8_c : entity work.A8_error_quantization
    generic map(BITNESS => BITNESS, MAX_VAL => MAX_VAL)
    port map
    (
      iErrorVal => sS3Err7C, iPx => sS3PxC, iSign => sReg2.Sign,
      oErrorVal => sS3Err8C, oRx => open);

  u_a9_c : entity work.A9_modulo_reduction
    generic map(BITNESS => BITNESS, MAX_VAL => MAX_VAL)
    port map
      (iErrorVal => sS3Err8C, oErrorVal => sS3Err9C);

  -- +1 chain (ΔCq = +1)
  u_a6_p : entity work.A6_prediction_correction
    generic map(BITNESS => BITNESS, MAX_VAL => MAX_VAL)
    port map
      (iPx => sS3Px, iSign => sReg2.Sign, iCq => sS3CqP1, oPx => sS3PxP);

  u_a7_p : entity work.A7_prediction_error
    generic map(BITNESS => BITNESS)
    port map
    (
      iIx => sReg2.Ix(BITNESS - 1 downto 0), iPx => sS3PxP,
      iSign => sReg2.Sign, oErrorVal => sS3Err7P);

  u_a8_p : entity work.A8_error_quantization
    generic map(BITNESS => BITNESS, MAX_VAL => MAX_VAL)
    port map
    (
      iErrorVal => sS3Err7P, iPx => sS3PxP, iSign => sReg2.Sign,
      oErrorVal => sS3Err8P, oRx => open);

  u_a9_p : entity work.A9_modulo_reduction
    generic map(BITNESS => BITNESS, MAX_VAL => MAX_VAL)
    port map
      (iErrorVal => sS3Err8P, oErrorVal => sS3Err9P);

  -- −1 chain (ΔCq = −1)
  u_a6_m : entity work.A6_prediction_correction
    generic map(BITNESS => BITNESS, MAX_VAL => MAX_VAL)
    port map
      (iPx => sS3Px, iSign => sReg2.Sign, iCq => sS3CqM1, oPx => sS3PxM);

  u_a7_m : entity work.A7_prediction_error
    generic map(BITNESS => BITNESS)
    port map
    (
      iIx => sReg2.Ix(BITNESS - 1 downto 0), iPx => sS3PxM,
      iSign => sReg2.Sign, oErrorVal => sS3Err7M);

  u_a8_m : entity work.A8_error_quantization
    generic map(BITNESS => BITNESS, MAX_VAL => MAX_VAL)
    port map
    (
      iErrorVal => sS3Err7M, iPx => sS3PxM, iSign => sReg2.Sign,
      oErrorVal => sS3Err8M, oRx => open);

  u_a9_m : entity work.A9_modulo_reduction
    generic map(BITNESS => BITNESS, MAX_VAL => MAX_VAL)
    port map
      (iErrorVal => sS3Err8M, oErrorVal => sS3Err9M);

  -- ΔCq from live Stage-4 A.13. On miss, sDeltaCq is irrelevant (sFwdRegHit=0).
  sDeltaCq <= sS4CqNew - sReg3.Cq;

  sSpecUseM <= '1' when sFwdRegHit = '1' and sDeltaCq < 0 else
    '0';
  sSpecUseP <= '1' when sFwdRegHit = '1' and sDeltaCq > 0 else
    '0';

  sS3Err9Sel <= sS3Err9M when sSpecUseM = '1' else
    sS3Err9P when sSpecUseP = '1' else
    sS3Err9C;

  -- ═══════════════════════════════════════════════════════════════════
  -- Stage 3 — RI: A.18 → A.19, A.20 (A.10 moved to Stage 4, shared)
  -- ═══════════════════════════════════════════════════════════════════
  u_a18 : entity work.A18_run_interruption_prediction_error
    generic map(BITNESS => BITNESS)
    port map
    (
      iRItype => sReg2.RItype,
      iRa     => sReg2.Ra(BITNESS - 1 downto 0),
      iRb     => sReg2.Rb(BITNESS - 1 downto 0),
      iIx     => sReg2.Ix(BITNESS - 1 downto 0),
      oPx     => sS3RiPx,
      oErrval => sS3RiErr18
    );

  u_a19 : entity work.A19_run_interruption_error
    generic map(BITNESS => BITNESS, MAX_VAL => MAX_VAL)
    port map
    (
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

  -- A.20: single context read returns (Aq, Nq) for Q ∈ {365, 366}.
  u_a20 : entity work.A20_compute_temp
    port map
    (
      iRItype => sReg2.RItype,
      iAq     => sS3Aq,
      iNq     => sS3Nq,
      oTemp   => sS3RiTemp
    );

  -- ═══════════════════════════════════════════════════════════════════
  -- Register 3 (Stage 3 → Stage 4) — carry per-mode Errval / Temp / Sign
  -- ═══════════════════════════════════════════════════════════════════
  process (iClk)
    variable v : t_pipeline_token;
  begin
    if rising_edge(iClk) then
      if iRst = '1' then
        sReg3    <= CO_TOKEN_NONE;
        sReg3V   <= '0';
        sReg3EOI <= '0';
      else
        v      := sReg2;
        v.Aq   := sS3Aq;
        v.Bq   := sS3Bq;
        v.Cq   := sS3Cq;
        v.Nq   := sS3Nq;
        v.Nn   := sS3Nn;
        v.Temp := (others => '0');
        case sReg2.mode is
          when TOKEN_REGULAR =>
            v.Errval := resize(sS3Err9Sel, CO_ERROR_VALUE_WIDTH_STD);
          when TOKEN_RUN_INTERRUPTION =>
            v.Errval := resize(sS3RiErr19, CO_ERROR_VALUE_WIDTH_STD);
            v.Sign   := sS3RiSign;
            v.Temp   := sS3RiTemp;
          when others =>
            null;
        end case;
        if sReg2V = '0' then
          v := CO_TOKEN_NONE;
        end if;
        sReg3    <= v;
        sReg3V   <= sReg2V;
        sReg3EOI <= sReg2EOI;
      end if;
    end if;
  end process;

  -- ═══════════════════════════════════════════════════════════════════
  -- Stage 4 — Shared A.10; regular A.12 + A.13; RI A.23
  -- A.10's iAq is muxed: regular → Aq, RI → Temp (from A.20 via Reg3).
  -- ═══════════════════════════════════════════════════════════════════
  sS4AqSel <= sReg3.Temp when sReg3.mode = TOKEN_RUN_INTERRUPTION else
    sReg3.Aq;

  u_a10 : entity work.A10_compute_k
    port map
    (
      iNq => sReg3.Nq,
      iAq => sS4AqSel,
      oK  => sS4K
    );

  u_a12 : entity work.A12_variables_update
    generic map(BITNESS => BITNESS)
    port map
    (
      iErrorVal => sReg3.Errval(BITNESS downto 0),
      iAq       => sReg3.Aq,
      iBq       => sReg3.Bq,
      iNq       => sReg3.Nq,
      oAq       => sS4AqNew,
      oBq       => sS4BqMid,
      oNq       => sS4NqNew
    );

  u_a13 : entity work.A13_update_bias
    port map
    (
      iBq => sS4BqMid,
      iNq => sS4NqNew,
      iCq => sReg3.Cq,
      oBq => sS4BqNew,
      oCq => sS4CqNew
    );

  u_a23 : entity work.A23_run_interruption_update
    port map
    (
      iErrval => sReg3.Errval(BITNESS downto 0),
      iRItype => sReg3.RItype,
      iAq     => sReg3.Aq,
      iNq     => sReg3.Nq,
      iNn     => sReg3.Nn,
      oAq     => sS4RiAqNew,
      oNq     => sS4RiNqNew,
      oNn     => sS4RiNnNew
    );

  -- ═══════════════════════════════════════════════════════════════════
  -- Register 4 (Stage 4 → Stage 5)
  -- ═══════════════════════════════════════════════════════════════════
  process (iClk)
    variable v : t_pipeline_token;
  begin
    if rising_edge(iClk) then
      if iRst = '1' then
        sReg4    <= CO_TOKEN_NONE;
        sReg4V   <= '0';
        sReg4EOI <= '0';
      else
        v   := sReg3;
        v.k := resize(sS4K, CO_K_WIDTH_STD);
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
  -- Stage 5 — Regular: A.11; RI: A.21 + A.22; shared: A.11.1
  -- ═══════════════════════════════════════════════════════════════════
  u_a11 : entity work.A11_error_mapping
    port map
    (
      iK              => sReg4.k,
      iBq             => sReg4.Bq,
      iNq             => sReg4.Nq,
      iErrorVal       => sReg4.Errval,
      oMappedErrorVal => sS5MErrval
    );

  u_a21 : entity work.A21_compute_map
    port map
    (
      iK      => sReg4.k,
      iErrval => sReg4.Errval,
      iNn     => sReg4.Nn,
      iNq     => sReg4.Nq,
      oMap    => sS5RiMap
    );

  u_a22 : entity work.A22_errval_mapping
    port map
    (
      iErrval   => sReg4.Errval,
      iRItype   => sReg4.RItype,
      iMap      => sS5RiMap,
      oEMErrval => sS5RiEMErrval
    );

  sS5GolMErr <= sS5MErrval when sReg4.mode = TOKEN_REGULAR else
    sS5RiEMErrval;

  u_a11_1 : entity work.A11_1_golomb_encoder
    port map
    (
      iK              => sReg4.k,
      iMappedErrorVal => sS5GolMErr,
      oUnaryZeros     => sS5Unary,
      oSuffixLen      => sS5SufLen,
      oSuffixVal      => sS5SufVal
    );

  -- ═══════════════════════════════════════════════════════════════════
  -- Output — bit packer → byte stuffer → framer
  -- ═══════════════════════════════════════════════════════════════════
  sBpRawV <= '1' when sReg4V = '1'
    and (sReg4.mode = TOKEN_RUN_INTERRUPTION or sReg4.mode = TOKEN_RAW)
    else
    '0';
  sBpGolV <= '1' when sReg4V = '1'
    and (sReg4.mode = TOKEN_REGULAR or sReg4.mode = TOKEN_RUN_INTERRUPTION)
    else
    '0';

  u_bit_packer : entity work.A11_2_bit_packer
    port map
    (
      iClk            => iClk,
      iRst            => iRst,
      iFlush          => sBpFlush,
      iRawValid       => sBpRawV,
      iRawLen         => sReg4.RawLen,
      iRawVal         => sReg4.RawVal,
      iGolombValid    => sBpGolV,
      iUnaryZeros     => sS5Unary,
      iSuffixLen      => sS5SufLen,
      iSuffixVal      => sS5SufVal,
      iReady          => sBsReady,
      oWord           => sBpWord,
      oWordValid      => sBpWordV,
      oBufferOverflow => sBpOverflow
    );

  u_byte_stuffer : entity work.byte_stuffer
    port map
    (
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
      BITNESS          => BITNESS,
      OUT_WIDTH        => OUT_WIDTH,
      MAX_IMAGE_WIDTH  => MAX_IMAGE_WIDTH,
      MAX_IMAGE_HEIGHT => MAX_IMAGE_HEIGHT
    )
    port map
    (
      iClk          => iClk,
      iRst          => iRst,
      iStart        => sFramerStart,
      iImageWidth   => sImageWidth,
      iImageHeight  => sImageHeight,
      iEOI          => sFramerEOI,
      iBsWord       => sBsWord,
      iBsWordValid  => sBsWordV,
      iBsValidBytes => sBsValidB,
      oBsReady      => sFramerBsRdy,
      oWord         => oData,
      oWordValid    => oValid,
      oValidBytes   => sFramerVBytes,
      oLast         => oLast,
      iReady        => iReady
    );

  -- AXI-Stream tkeep: one bit per byte, MSB = first byte transmitted.
  -- Byte 0 occupies oData(OUT_WIDTH-1 downto OUT_WIDTH-8) → oKeep(OUT_WIDTH/8 - 1).
  -- For a count of N valid bytes, the top N bits of oKeep are '1'.
  gen_keep : for i in 0 to OUT_WIDTH / 8 - 1 generate
    oKeep(OUT_WIDTH / 8 - 1 - i) <= '1' when sFramerVBytes > i else
    '0';
  end generate;

  -- ═══════════════════════════════════════════════════════════════════
  -- Flush / framer control
  -- ═══════════════════════════════════════════════════════════════════
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

  process (iClk)
  begin
    if rising_edge(iClk) then
      if iRst = '1' then
        sImageActive <= '0';
      elsif sValid = '1' and sImageActive = '0' then
        sImageActive <= '1';
      elsif sEoiPipe(4) = '1' then
        sImageActive <= '0';
      end if;
    end if;
  end process;
