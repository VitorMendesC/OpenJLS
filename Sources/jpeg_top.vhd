----------------------------------------------------------------------------------
-- Company:
-- Engineer:    Vitor Mendes Camilo
-- 
-- Create Date: 08/30/2025 11:45:14 PM
-- Design Name: 
-- Module Name: jpeg_top - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:                 Top level file
-- 
--                TODO: clocked modules already have output register, check if you aren't double registering 
--                TODO: check if clocked modules actually have output registers
--
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use work.Common.all;

entity jpeg_top is
  generic (
    BITNESS      : natural range 8 to 16 := 12;
    OUT_WIDTH    : natural               := 32;
    BUFFER_WIDTH : natural               := 2 * OUT_WIDTH -- should be >= 2*OUT_WIDTH
  );
  port (
    iClk       : in std_logic;
    iRst       : in std_logic;
    iPixel     : in std_logic_vector (BITNESS - 1 downto 0);
    iValid     : in std_logic;
    oWord      : out std_logic_vector (OUT_WIDTH - 1 downto 0);
    oWordValid : out std_logic
  );
end jpeg_top;

architecture Behavioral of jpeg_top is
  -- Bitstream packing sizes
  -- TODO: Check ALL of these values
  constant C_RESET         : natural                           := 64;
  constant C_RANGE         : natural                           := 2 ** BITNESS; -- modulo reduction RANGE
  constant C_QBPP          : natural                           := BITNESS; -- ceil(log2(RANGE))
  constant C_MAX_C         : natural                           := 127;
  constant C_MIN_C         : natural                           := 0;
  constant C_MAX_K         : natural                           := 12;
  constant C_MAX_VAL       : natural                           := 2 ** BITNESS - 1;
  constant UNARY_WIDTH     : natural                           := 6;
  constant SUFFIX_WIDTH    : natural                           := 16;
  constant SUFFIXLEN_WIDTH : natural                           := 5;
  constant C_A_WIDTH       : natural                           := clog2(C_RESET * C_MAX_VAL + 1);
  constant C_B_WIDTH       : natural                           := clog2(C_RESET) + 1;
  constant C_C_WIDTH       : natural                           := clog2(C_MAX_C + 1) + 1;
  constant C_N_WIDTH       : natural                           := clog2(C_RESET);
  constant C_K_WIDTH       : natural                           := 4;
  constant C_LIMIT         : natural                           := 32;
  constant C_TOTLEN_WIDTH  : natural                           := clog2(C_LIMIT);
  constant C_CONTEXT_DEPTH : natural                           := 367;
  constant cRange          : natural                           := C_MAX_VAL + 1;
  constant cAInit          : unsigned (C_A_WIDTH - 1 downto 0) := to_unsigned(maximum(2, (cRange + 2 ** 5)/(2 ** 6)), A_WIDTH);
  constant cBInit          : unsigned (C_B_WIDTH - 1 downto 0) := to_unsigned(0, C_B_WIDTH);
  constant cCInit          : unsigned (C_C_WIDTH - 1 downto 0) := to_unsigned(0, C_C_WIDTH);
  constant cNInit          : unsigned (C_N_WIDTH - 1 downto 0) := to_unsigned(1, C_N_WIDTH);

  -- Stage 0/1: input pixels and neighbors (placeholder: all from iPixel)
  signal sA_1, sB_1, sC_1, sD_1 : unsigned(BITNESS - 1 downto 0) := (others => '0');
  signal sIx_1                  : unsigned(BITNESS - 1 downto 0) := (others => '0');

  -- Stage 1: gradient computation
  signal wD1_1, wD2_1, wD3_1 : signed(BITNESS downto 0);
  signal sValid_1            : std_logic;

  -- Stage 2: mode selection (inputs are registered outputs of stage 1)
  signal sD1_2, sD2_2, sD3_2 : signed(BITNESS downto 0) := (others => '0');
  signal wModeRegular_2      : std_logic;
  signal wModeRun_2          : std_logic;
  signal sValid_2            : std_logic;

  -- Stage 3: quantization of gradients
  signal sD1_3, sD2_3, sD3_3 : signed(BITNESS downto 0) := (others => '0');
  signal sModeRegular_3      : std_logic                := '0';
  signal sModeRun_3          : std_logic                := '0';
  signal wQ1_3, wQ2_3, wQ3_3 : signed(3 downto 0);
  signal sValid_3            : std_logic;

  -- Stage 4: gradient merging
  signal sQ1_4, sQ2_4, sQ3_4 : signed(3 downto 0) := (others => '0');
  signal wQ1_4, wQ2_4, wQ3_4 : signed(3 downto 0);
  signal wSign_4             : std_logic;
  signal sValid_4            : std_logic;

  -- Stage 5: Q mapping
  signal sQ1_5, sQ2_5, sQ3_5 : signed(3 downto 0) := (others => '0');
  signal sSign_5             : std_logic          := '0';
  signal wQ_5                : unsigned(8 downto 0);
  signal sValid_5            : std_logic;

  -- Stage 6: predictor (also pipeline A/B/C through to here)
  signal sQ_6                   : unsigned(8 downto 0)           := (others => '0');
  signal sQ6_1                  : unsigned(8 downto 0)           := (others => '0');
  signal sQ_11                  : unsigned(8 downto 0)           := (others => '0');
  signal sA_2, sA_3, sA_4, sA_5 : unsigned(BITNESS - 1 downto 0) := (others => '0');
  signal sA_6_1, sA_6_2         : unsigned(BITNESS - 1 downto 0) := (others => '0');
  signal sB_2, sB_3, sB_4, sB_5 : unsigned(BITNESS - 1 downto 0) := (others => '0');
  signal sB_6_1, sB_6_2         : unsigned(BITNESS - 1 downto 0) := (others => '0');
  signal sC_2, sC_3, sC_4, sC_5 : unsigned(BITNESS - 1 downto 0) := (others => '0');
  signal sC_6_1, sC_6_2         : unsigned(BITNESS - 1 downto 0) := (others => '0');
  signal wPxPred_6_2            : unsigned(BITNESS - 1 downto 0);
  signal sValid_6               : std_logic;
  signal sValid_6_1             : std_logic := '0';
  signal sValid_6_2             : std_logic := '0';

  -- Reset pipeline (stage-aligned)
  signal sRst_1   : std_logic := '0';
  signal sRst_2   : std_logic := '0';
  signal sRst_3   : std_logic := '0';
  signal sRst_4   : std_logic := '0';
  signal sRst_5   : std_logic := '0';
  signal sRst_6_1 : std_logic := '0';
  signal sRst_6_2 : std_logic := '0';
  signal sRst_7   : std_logic := '0';
  signal sRst_8   : std_logic := '0';
  signal sRst_9   : std_logic := '0';
  signal sRst_10  : std_logic := '0';
  signal sRst_11  : std_logic := '0';
  signal sRst_12  : std_logic := '0';

  -- Stage 7: prediction correction (pipeline sign and Cq)
  signal sPxPred_7 : unsigned(BITNESS - 1 downto 0)   := (others => '0');
  signal sSign_6   : std_logic                        := '0';
  signal sSign_6_1 : std_logic                        := '0';
  signal sSign_6_2 : std_logic                        := '0';
  signal sSign_7   : std_logic                        := '0';
  signal sCq_7     : unsigned(C_C_WIDTH - 1 downto 0) := (others => '0');
  signal wPxCorr_7 : unsigned(BITNESS - 1 downto 0);
  signal sValid_7  : std_logic;

  -- Stage 8: prediction error
  signal sPxCorr_8                                       : unsigned(BITNESS - 1 downto 0) := (others => '0');
  signal sIx_2, sIx_3, sIx_4, sIx_5, sIx_6, sIx_7, sIx_8 : unsigned(BITNESS - 1 downto 0) := (others => '0');
  signal sIx_6_1, sIx_6_2                                : unsigned(BITNESS - 1 downto 0) := (others => '0');
  signal sSign_8                                         : std_logic                      := '0';
  signal wErr_8                                          : signed(BITNESS downto 0);
  -- Context vars start at stage 8; pipeline to stage 10
  signal sAq_8_in  : unsigned(C_A_WIDTH - 1 downto 0) := (others => '0');
  signal sNq_8_in  : unsigned(C_N_WIDTH - 1 downto 0) := (others => '0');
  signal sAq_9_in  : unsigned(C_A_WIDTH - 1 downto 0) := (others => '0');
  signal sNq_9_in  : unsigned(C_N_WIDTH - 1 downto 0) := (others => '0');
  signal sAq_10_in : unsigned(C_A_WIDTH - 1 downto 0) := (others => '0');
  signal sNq_10_in : unsigned(C_N_WIDTH - 1 downto 0) := (others => '0');
  signal sBq_8_in  : signed(C_B_WIDTH - 1 downto 0)   := (others => '0');
  signal sBq_9_in  : signed(C_B_WIDTH - 1 downto 0)   := (others => '0');
  signal sValid_8  : std_logic;

  -- Stage 9: modulo reduction
  signal sErr_9   : signed(BITNESS downto 0) := (others => '0');
  signal wErr_9   : signed(BITNESS downto 0);
  signal sValid_9 : std_logic;

  -- Stage 10: error mapping and variables update (+ compute k)
  signal sErr_10   : signed(BITNESS downto 0)       := (others => '0');
  signal sBq_10_in : signed(C_B_WIDTH - 1 downto 0) := (others => '0');
  -- k computed from stage 8; pipeline to stage 10 and 11
  signal sK_9          : unsigned(C_K_WIDTH - 1 downto 0) := (others => '0');
  signal sK_10         : unsigned(C_K_WIDTH - 1 downto 0) := (others => '0');
  signal wK_8          : unsigned(C_K_WIDTH - 1 downto 0);
  signal wMappedErr_10 : unsigned(BITNESS downto 0);
  signal wAq_10        : unsigned(C_A_WIDTH - 1 downto 0);
  signal wBq_10        : signed(C_B_WIDTH - 1 downto 0);
  signal wNq_10        : unsigned(C_N_WIDTH - 1 downto 0);
  signal sValid_10     : std_logic;

  -- Stage 11: Golomb encoder + bias update
  signal sMappedErr_11    : unsigned(BITNESS downto 0)                   := (others => '0');
  signal sK_11            : unsigned(C_K_WIDTH - 1 downto 0)             := (others => '0');
  signal sAq_11           : unsigned(C_A_WIDTH - 1 downto 0)             := (others => '0');
  signal sBq_11           : signed(C_B_WIDTH - 1 downto 0)               := (others => '0');
  signal sNq_11           : unsigned(C_N_WIDTH - 1 downto 0)             := (others => '0');
  signal sCq_11           : unsigned(C_C_WIDTH - 1 downto 0)             := (others => '0');
  signal sContextData_11  : std_logic_vector(C_A_WIDTH * 4 - 1 downto 0) := (others => '0');
  signal wContextData_6_2 : std_logic_vector(C_A_WIDTH * 4 - 1 downto 0);
  signal wUnaryZeros_11   : unsigned(UNARY_WIDTH - 1 downto 0);
  signal wSuffixLen_11    : unsigned(SUFFIXLEN_WIDTH - 1 downto 0);
  signal wSuffixVal_11    : unsigned(SUFFIX_WIDTH - 1 downto 0);
  signal wTotalLen_11     : unsigned(C_TOTLEN_WIDTH - 1 downto 0);
  signal wIsEscape_11     : std_logic;
  signal wBqNew_11        : signed(C_B_WIDTH - 1 downto 0);
  signal wCqNew_11        : unsigned(C_C_WIDTH - 1 downto 0);
  signal sValid_11        : std_logic;

  -- Stage 12: bit packer inputs/outputs
  signal sUnaryZeros_12 : unsigned(UNARY_WIDTH - 1 downto 0)     := (others => '0');
  signal sSuffixLen_12  : unsigned(SUFFIXLEN_WIDTH - 1 downto 0) := (others => '0');
  signal sSuffixVal_12  : unsigned(SUFFIX_WIDTH - 1 downto 0)    := (others => '0');
  signal sValid_12      : std_logic                              := '0';
  signal sWord_12       : std_logic_vector(OUT_WIDTH - 1 downto 0);
  signal sWordValid_12  : std_logic;

begin

  -----------------------------------------------------------------
  -- Stage 1
  -----------------------------------------------------------------

  A1_gradient_comp_inst : entity work.A1_gradient_comp
    generic map(
      BITNESS => BITNESS
    )
    port map
    (
      iA  => sA_1,
      iB  => sB_1,
      iC  => sC_1,
      iD  => sD_1,
      oD1 => wD1_1,
      oD2 => wD2_1,
      oD3 => wD3_1
    );

  -----------------------------------------------------------------
  -- Stage 2
  -----------------------------------------------------------------

  A3_mode_selection_inst : entity work.A3_mode_selection
    generic map(
      BITNESS => BITNESS
    )
    port map
    (
      iD1          => sD1_2,
      iD2          => sD2_2,
      iD3          => sD3_2,
      oModeRegular => wModeRegular_2,
      oModeRun     => wModeRun_2
    );

  -----------------------------------------------------------------
  -- Stage 3
  -----------------------------------------------------------------

  A4_quantization_gradients_inst : entity work.A4_quantization_gradients
    generic map(
      BITNESS => BITNESS
    )
    port map
    (
      iD1 => sD1_3,
      iD2 => sD2_3,
      iD3 => sD3_3,
      oQ1 => wQ1_3,
      oQ2 => wQ2_3,
      oQ3 => wQ3_3
    );

  -----------------------------------------------------------------
  -- Stage 4
  -----------------------------------------------------------------

  A4_1_quant_gradient_merging_inst : entity work.A4_1_quant_gradient_merging
    port map
    (
      iQ1   => sQ1_4,
      iQ2   => sQ2_4,
      iQ3   => sQ3_4,
      oQ1   => wQ1_4,
      oQ2   => wQ2_4,
      oQ3   => wQ3_4,
      oSign => wSign_4
    );

  -----------------------------------------------------------------
  -- Stage 5
  -----------------------------------------------------------------

  A4_2_Q_mapping_inst : entity work.A4_2_Q_mapping
    port map
    (
      iQ1 => sQ1_5,
      iQ2 => sQ2_5,
      iQ3 => sQ3_5,
      oQ  => wQ_5
    );

  -----------------------------------------------------------------
  -- Stage 6.1
  -----------------------------------------------------------------

  C_context_ram : entity work.context_ram
    generic map(
      WORD_WIDTH => C_C_WIDTH, -- NOTE: check
      DEPTH      => C_CONTEXT_DEPTH,
      MAX_VAL    => C_MAX_VAL
    )
    port map
    (
      iClk    => iClk,
      iRst    => sRst_6_1,
      iValid  => sValid_6_2,
      iWrEn   => sValid_11, -- TODO: check if correct stage
      iQRead  => sQ6_1,
      iQWrite => sQ_11, -- TODO: check if correct stage
      iData   => sContextData_11,
      oData   => wContextData_6_2
    );

  -----------------------------------------------------------------
  -- Stage 6.2
  -----------------------------------------------------------------

  A5_edge_detecting_predictor_inst : entity work.A5_edge_detecting_predictor
    generic map(
      BITNESS => BITNESS
    )
    port map
    (
      iA  => sA_6_2,
      iB  => sB_6_2,
      iC  => sC_6_2,
      oPx => wPxPred_6_2
    );

  -----------------------------------------------------------------
  -- Stage 7
  -----------------------------------------------------------------

  A6_prediction_correction_inst : entity work.A6_prediction_correction
    generic map(
      BITNESS => BITNESS,
      C_WIDTH => C_C_WIDTH,
      MAX_VAL => C_MAX_VAL
    )
    port map
    (
      iPx   => sPxPred_7,
      iSign => sSign_7,
      iCq   => sCq_7,
      oPx   => wPxCorr_7
    );

  -----------------------------------------------------------------
  -- Stage 8
  -----------------------------------------------------------------

  A7_prediction_error_inst : entity work.A7_prediction_error
    generic map(
      BITNESS => BITNESS
    )
    port map
    (
      iIx         => sIx_8,
      iPx         => sPxCorr_8,
      iSign       => sSign_8,
      oErrorValue => wErr_8
    );

  A10_compute_k_inst : entity work.A10_compute_k
    generic map(
      N_WIDTH => C_N_WIDTH,
      A_WIDTH => C_A_WIDTH,
      K_WIDTH => C_K_WIDTH,
      MAX_K   => C_MAX_K
    )
    port map
    (
      iNq => sNq_8_in,
      iAq => sAq_8_in,
      oK  => wK_8
    );

  -----------------------------------------------------------------
  -- Stage 9
  -----------------------------------------------------------------

  A9_modulo_reduction_inst : entity work.A9_modulo_reduction
    generic map(
      BITNESS => BITNESS,
      C_RANGE => C_RANGE
    )
    port map
    (
      iErrorValue => sErr_9,
      oErrorValue => wErr_9
    );

  -----------------------------------------------------------------
  -- Stage 10
  -----------------------------------------------------------------

  A11_error_mapping_inst : entity work.A11_error_mapping
    generic map(
      BITNESS => BITNESS,
      N_WIDTH => C_N_WIDTH,
      B_WIDTH => C_B_WIDTH,
      K_WIDTH => C_K_WIDTH
    )
    port map
    (
      iK           => sK_10,
      iBq          => sBq_10_in,
      iNq          => sNq_10_in,
      iErrorValue  => sErr_10,
      oMappedError => wMappedErr_10
    );

  A12_variables_update_inst : entity work.A12_variables_update
    generic map(
      BITNESS => BITNESS,
      A_WIDTH => C_A_WIDTH,
      B_WIDTH => C_B_WIDTH,
      N_WIDTH => C_N_WIDTH,
      RESET   => C_RESET
    )
    port map
    (
      iErrorValue => sErr_10,
      iAq         => sAq_10_in,
      iBq         => sBq_10_in,
      iNq         => sNq_10_in,
      oAq         => wAq_10,
      oBq         => wBq_10,
      oNq         => wNq_10
    );

  -----------------------------------------------------------------
  -- Stage 11
  -----------------------------------------------------------------

  A11_1_golomb_encoder_inst : entity work.A11_1_golomb_encoder
    generic map(
      BITNESS         => BITNESS,
      K_WIDTH         => C_K_WIDTH,
      QBPP            => C_QBPP,
      LIMIT           => C_LIMIT,
      UNARY_WIDTH     => UNARY_WIDTH,
      SUFFIX_WIDTH    => SUFFIX_WIDTH,
      SUFFIXLEN_WIDTH => SUFFIXLEN_WIDTH,
      TOTLEN_WIDTH    => C_TOTLEN_WIDTH
    )
    port map
    (
      iK          => sK_11,
      iMapErrval  => sMappedErr_11,
      oUnaryZeros => wUnaryZeros_11,
      oSuffixLen  => wSuffixLen_11,
      oSuffixVal  => wSuffixVal_11,
      oTotalLen   => wTotalLen_11,
      oIsEscape   => wIsEscape_11
    );

  A13_update_bias_inst : entity work.A13_update_bias
    generic map(
      B_WIDTH => C_B_WIDTH,
      C_WIDTH => C_C_WIDTH,
      N_WIDTH => C_N_WIDTH,
      MIN_C   => C_MIN_C,
      MAX_C   => C_MAX_C
    )
    port map
    (
      iBq => sBq_11,
      iCq => sCq_11,
      iNq => sNq_11,
      oBq => wBqNew_11,
      oCq => wCqNew_11
    );

  -----------------------------------------------------------------
  -- Stage 12
  -----------------------------------------------------------------

  -- TODO: Memory write 

  A11_2_bit_packer_inst : entity work.A11_2_bit_packer
    generic map(
      LIMIT           => C_LIMIT,
      OUT_WIDTH       => OUT_WIDTH,
      BUFFER_WIDTH    => BUFFER_WIDTH,
      UNARY_WIDTH     => UNARY_WIDTH,
      SUFFIX_WIDTH    => SUFFIX_WIDTH,
      SUFFIXLEN_WIDTH => SUFFIXLEN_WIDTH
    )
    port map
    (
      iClk            => iClk,
      iRst            => sRst_12,
      iValid          => sValid_12,
      iUnaryZeros     => sUnaryZeros_12,
      iSuffixLen      => sSuffixLen_12,
      iSuffixVal      => sSuffixVal_12,
      iFlush          => '0',
      iReady          => '1',
      oWord           => sWord_12,
      oWordValid      => sWordValid_12,
      oBufferOverflow => open
    );

  -- Single pipeline register process: advance one stage per clock
  pPipeline : process (iClk)
  begin
    if rising_edge(iClk) then
      if iRst = '1' then
        -- Reset stage 0/1
        sA_1     <= (others => '0');
        sB_1     <= (others => '0');
        sC_1     <= (others => '0');
        sD_1     <= (others => '0');
        sIx_1    <= (others => '0');
        sValid_1 <= '0';

        -- Reset stage 2/3 inputs and mode
        sD1_2          <= (others => '0');
        sD2_2          <= (others => '0');
        sD3_2          <= (others => '0');
        sD1_3          <= (others => '0');
        sD2_3          <= (others => '0');
        sD3_3          <= (others => '0');
        sModeRegular_3 <= '0';
        sModeRun_3     <= '0';
        sValid_2       <= '0';
        sValid_3       <= '0';

        -- Reset stages 4/5
        sQ1_4    <= (others => '0');
        sQ2_4    <= (others => '0');
        sQ3_4    <= (others => '0');
        sQ1_5    <= (others => '0');
        sQ2_5    <= (others => '0');
        sQ3_5    <= (others => '0');
        sSign_5  <= '0';
        sValid_4 <= '0';
        sValid_5 <= '0';

        -- Reset stage 6/7
        sQ_6      <= (others => '0');
        sA_2      <= (others => '0');
        sA_3      <= (others => '0');
        sA_4      <= (others => '0');
        sA_5      <= (others => '0');
        sA_6_2    <= (others => '0');
        sB_2      <= (others => '0');
        sB_3      <= (others => '0');
        sB_4      <= (others => '0');
        sB_5      <= (others => '0');
        sB_6_2    <= (others => '0');
        sC_2      <= (others => '0');
        sC_3      <= (others => '0');
        sC_4      <= (others => '0');
        sC_5      <= (others => '0');
        sC_6_2    <= (others => '0');
        sPxPred_7 <= (others => '0');
        sSign_6   <= '0';
        sSign_7   <= '0';
        sCq_7     <= (others => '0');
        sValid_6  <= '0';
        sValid_7  <= '0';

        -- Reset stage 8/9
        sPxCorr_8 <= (others => '0');
        sIx_2     <= (others => '0');
        sIx_3     <= (others => '0');
        sIx_4     <= (others => '0');
        sIx_5     <= (others => '0');
        sIx_6     <= (others => '0');
        sIx_7     <= (others => '0');
        sIx_8     <= (others => '0');
        sSign_8   <= '0';
        sErr_9    <= (others => '0');
        sAq_8_in  <= (others => '0');
        sAq_9_in  <= (others => '0');
        sAq_10_in <= (others => '0');
        sNq_8_in  <= (others => '0');
        sNq_9_in  <= (others => '0');
        sNq_10_in <= (others => '0');
        sBq_8_in  <= (others => '0');
        sBq_9_in  <= (others => '0');
        sValid_8  <= '0';
        sValid_9  <= '0';

        -- Reset stage 10/11
        sErr_10       <= (others => '0');
        sBq_10_in     <= (others => '0');
        sK_9          <= (others => '0');
        sK_10         <= (others => '0');
        sMappedErr_11 <= (others => '0');
        sK_11         <= (others => '0');
        sAq_11        <= (others => '0');
        sBq_11        <= (others => '0');
        sNq_11        <= (others => '0');
        sCq_11        <= (others => '0');
        sValid_10     <= '0';
        sValid_11     <= '0';

        -- Reset stage 12
        sUnaryZeros_12 <= (others => '0');
        sSuffixLen_12  <= (others => '0');
        sSuffixVal_12  <= (others => '0');
        sValid_12      <= '0';

        -- Reset pipeline: assert reset on all stages
        sRst_1  <= '1';
        sRst_2  <= '1';
        sRst_3  <= '1';
        sRst_4  <= '1';
        sRst_5  <= '1';
        sRst_6  <= '1';
        sRst_7  <= '1';
        sRst_8  <= '1';
        sRst_9  <= '1';
        sRst_10 <= '1';
        sRst_11 <= '1';
        sRst_12 <= '1';

      else

        -- NOTE: Debug values
        sCq_7    <= to_unsigned(5, C_C_WIDTH);
        sAq_8_in <= TO_UNSIGNED(10, sAq_8_in'length);
        sNq_8_in <= TO_UNSIGNED(1, sNq_8_in'length);
        sBq_8_in <= TO_SIGNED(-600, sBq_8_in'length);

        -- Stage 1 capture (placeholder neighborhood = iPixel)
        if iValid = '1' then
          sIx_1 <= unsigned(iPixel);
        end if;

        -- Valid
        sValid_1   <= iValid;
        sValid_2   <= sValid_1;
        sValid_3   <= sValid_2;
        sValid_4   <= sValid_3;
        sValid_5   <= sValid_4;
        sValid_6_1 <= sValid_5;
        sValid_6_2 <= sValid_6_1;
        sValid_7   <= sValid_6_2;
        sValid_8   <= sValid_7;
        sValid_9   <= sValid_8;
        sValid_10  <= sValid_9;
        sValid_11  <= sValid_10;
        sValid_12  <= sValid_11; -- always accept for now
        oWordValid <= sWordValid_12;

        -- Reset: pipeline through all stages (stage-aligned)
        sRst_1   <= iRst;
        sRst_2   <= sRst_1;
        sRst_3   <= sRst_2;
        sRst_4   <= sRst_3;
        sRst_5   <= sRst_4;
        sRst_6_1 <= sRst_5;
        sRst_6_2 <= sRst_6_1;
        sRst_7   <= sRst_6_2;
        sRst_8   <= sRst_7;
        sRst_9   <= sRst_8;
        sRst_10  <= sRst_9;
        sRst_11  <= sRst_10;
        sRst_12  <= sRst_11;

        -- Pixel input (Ix)
        sIx_2   <= sIx_1;
        sIx_3   <= sIx_2;
        sIx_4   <= sIx_3;
        sIx_5   <= sIx_4;
        sIx_6_1 <= sIx_5;
        sIx_6_2 <= sIx_6_1;
        sIx_7   <= sIx_6_2;
        sIx_8   <= sIx_7;

        -- Pixel neighbour values (a, b, c ,d)
        -- a
        sA_2   <= sA_1;
        sA_3   <= sA_2;
        sA_4   <= sA_3;
        sA_5   <= sA_4;
        sA_6_1 <= sA_5;
        sA_6_2 <= sA_6_1;
        -- b 
        sB_2   <= sB_1;
        sB_3   <= sB_2;
        sB_4   <= sB_3;
        sB_5   <= sB_4;
        sB_6_1 <= sB_5;
        sB_6_2 <= sB_6_1;
        -- c
        sC_2   <= sC_1;
        sC_3   <= sC_2;
        sC_4   <= sC_3;
        sC_5   <= sC_4;
        sC_6_1 <= sC_5;
        sC_6_2 <= sC_6_1;

        -- Gradients
        sD1_2 <= wD1_1;
        sD2_2 <= wD2_1;
        sD3_2 <= wD3_1;
        sD1_3 <= sD1_2;
        sD2_3 <= sD2_2;
        sD3_3 <= sD3_2;

        -- Modes
        sModeRegular_3 <= wModeRegular_2;
        sModeRun_3     <= wModeRun_2;

        -- Quantized gradients (Qi)
        sQ1_4 <= wQ1_3;
        sQ2_4 <= wQ2_3;
        sQ3_4 <= wQ3_3;
        sQ1_5 <= wQ1_4;
        sQ2_5 <= wQ2_4;
        sQ3_5 <= wQ3_4;

        -- Sign
        sSign_5   <= wSign_4;
        sSign_6_1 <= sSign_5;
        sSign_6_2 <= sSign_6_1;
        sSign_7   <= sSign_6_2;
        sSign_8   <= sSign_7;

        -- Mapped Q
        sQ_6 <= wQ_5;

        -- Predicted value (Px)
        sPxPred_7 <= wPxPred_6_2;

        -- Corrected predicted value (Px')
        sPxCorr_8 <= wPxCorr_7;

        -- Prediction error (Errval)
        sErr_9  <= wErr_8;
        sErr_10 <= wErr_9;

        -- Mapped error (MErval)
        sMappedErr_11 <= wMappedErr_10;

        -- Golomb parameter (k): pipeline from stage 8 -> 10 -> 11
        sK_9  <= wK_8;
        sK_10 <= sK_9;
        sK_11 <= sK_10;

        -- Context variables (A[Q], B[Q], N[Q]) pipeline: stage 8 -> 9 -> 10
        -- A[Q]
        sAq_9_in  <= sAq_8_in;
        sAq_10_in <= sAq_9_in;
        sAq_11    <= wAq_10;
        -- B[Q]
        sBq_9_in  <= sBq_8_in;
        sBq_10_in <= sBq_9_in;
        sBq_11    <= wBq_10;
        -- N[Q]
        sNq_9_in  <= sNq_8_in;
        sNq_10_in <= sNq_9_in;
        sNq_11    <= wNq_10;
        -- C[Q] 
        -- TODO: pipeline Cq from stage 7
        sCq_11 <= sCq_7;

        -- Stage 11 -> 12
        sUnaryZeros_12 <= wUnaryZeros_11;
        sSuffixLen_12  <= wSuffixLen_11;
        sSuffixVal_12  <= wSuffixVal_11;

        -- Stage 12 -> out
        oWord <= sWord_12;

      end if;
    end if;
  end process;

end Behavioral;
