----------------------------------------------------------------------------------
-- Engineer: Vitor Mendes Camilo
----------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.common.all;

library openlogic_base;
  use openlogic_base.olo_base_pkg_math.all;

entity context_ram is
  generic (
    RANGE_P         : positive := CO_RANGE_STD;
    RAM_DEPTH       : positive := 367;
    A_WIDTH         : positive := CO_AQ_WIDTH_STD;
    B_WIDTH         : positive := CO_BQ_WIDTH_STD;
    C_WIDTH         : positive := CO_CQ_WIDTH;
    N_WIDTH         : positive := CO_NQ_WIDTH_STD;
    TOTAL_WIDTH     : positive := CO_TOTAL_WIDTH_STD;
    RAM_MEMORY_TYPE : string   := "auto" -- Vendor-specific execept for auto, usually is the best option too
  );
  port (
    iClk            : in    std_logic;
    iRst            : in    std_logic;
    iWrAddr         : in    std_logic_vector(log2ceil(RAM_DEPTH) - 1 downto 0);
    iWrEn           : in    std_logic;
    iWrData         : in    std_logic_vector(TOTAL_WIDTH - 1 downto 0);
    iRdAddr         : in    std_logic_vector(log2ceil(RAM_DEPTH) - 1 downto 0);
    iRdEn           : in    std_logic;
    iEndOfImage     : in    std_logic;
    oRdData         : out   std_logic_vector(TOTAL_WIDTH - 1 downto 0)
  );
end entity context_ram;

architecture behavioral of context_ram is

  constant A_INIT      : natural := math_max(2, (RANGE_P + 32) / 64);
  constant B_INIT      : integer := 0;
  constant C_INIT      : integer := 0;
  constant N_INIT      : natural := 1;

  -- Packed init word (A | B | C | N)
  -- For run context (A | Nn | 0 | N)
  -- Nn also initializes to 0, like B
  constant CTX_INIT    : std_logic_vector(TOTAL_WIDTH - 1 downto 0) :=
                                                                       std_logic_vector(to_unsigned(A_INIT, A_WIDTH)) &
                                                                       std_logic_vector(to_signed(B_INIT, B_WIDTH)) &
                                                                       std_logic_vector(to_signed(C_INIT, C_WIDTH)) &
                                                                       std_logic_vector(to_unsigned(N_INIT, N_WIDTH));

  signal sUseInitValue : std_logic_vector(RAM_DEPTH - 1 downto 0); -- Indicates if init value should be used for each address
  signal sUseInitReg   : std_logic;                                -- Indicates if use init value for the address read last cycle
  signal sBramRdData   : std_logic_vector(TOTAL_WIDTH - 1 downto 0);

  -- Same-cycle write->read forwarding: rebuilds WBR on top of an RBW BRAM.
  signal sFwdSameReg   : std_logic;
  signal sWrDataReg    : std_logic_vector(TOTAL_WIDTH - 1 downto 0);

begin

  -- Accesses may be in flight on the FIRST reset cycle: the pipeline's valid
  -- registers clear synchronously, so the pre-reset valid still drives the
  -- enables that cycle. Harmless by construction — the re-arm wins over the
  -- read's flag-clear, a write lands in BRAM but stays masked by the re-armed
  -- init flag, and the read result is consumed by nothing (downstream is
  -- reset). Verified by directed cases in the module TB.

  olo_base_ram_sdp_inst : entity openlogic_base.olo_base_ram_sdp(rtl)
    generic map (
      DEPTH_G         => RAM_DEPTH,
      WIDTH_G         => TOTAL_WIDTH,
      ISASYNC_G       => false,
      RDLATENCY_G     => 1,
      RAMSTYLE_G      => RAM_MEMORY_TYPE,
      RAMBEHAVIOR_G   => "RBW",
      USEBYTEENABLE_G => false,
      INITSTRING_G    => "",
      INITFORMAT_G    => "NONE"
    )
    port map (
      Clk             => iClk,
      Wr_Addr         => iWrAddr,
      Wr_Ena          => iWrEn,
      Wr_Be           => open,
      Wr_Data         => iWrData,
      Rd_Clk          => open,
      Rd_Addr         => iRdAddr,
      Rd_Ena          => iRdEn,
      Rd_Data         => sBramRdData
    );

  p_init_tracker : process (iClk) is
  begin

    if rising_edge(iClk) then
      if (iRst = '1') then
        sUseInitValue <= (others => '1');
      else
        if (iRdEn = '1') then
          sUseInitReg                                  <= sUseInitValue(to_integer(unsigned(iRdAddr)));
          sUseInitValue(to_integer(unsigned(iRdAddr))) <= '0';
        end if;

        if (iEndOfImage = '1') then
          sUseInitValue <= (others => '1');
        end if;
      end if;
    end if;

  end process p_init_tracker;

  p_fwd : process (iClk) is
  begin

    if rising_edge(iClk) then
      if (iRst = '1') then
        sFwdSameReg <= '0';
        sWrDataReg  <= (others => '0');
      elsif (iRdEn = '1') then
        sFwdSameReg <= iWrEn and bool2bit(iWrAddr = iRdAddr);
        sWrDataReg  <= iWrData;
      end if;
    end if;

  end process p_fwd;

  oRdData <= CTX_INIT when sUseInitReg = '1' else
             sWrDataReg when sFwdSameReg = '1' else
             sBramRdData;

end architecture behavioral;
