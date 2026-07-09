-------------------------------------------------------------------------------------------------------------
-- Engineer:    Vitor Mendes Camilo
--
-- Module Name: openjls_axi - rtl
-- Description: AXI4-Stream + AXI4-Lite wrapper around openjls_top (flavor B).
--
--          Instantiates openjls_axis (flavor A) and adds an AXI4-Lite register
--          bank plus a reset controller. The core samples iImageWidth/
--          iImageHeight only while its synchronous reset is high, so
--          reconfiguration is expressed as: write WIDTH/HEIGHT, set CTRL.APPLY.
--          APPLY pulses the core reset for RESET_CYCLES clocks while the
--          registers are held stable; the AXI-Lite endpoint itself stays on
--          aresetn only, so the bus never disappears mid-reconfigure.
--          Back-to-back images of unchanged dimensions need no APPLY.
--
--          While the pulse is active STATUS.BUSY reads 1 and the core holds
--          s_axis_tready low, so a stream started too early stalls instead of
--          losing pixels. Writes to WIDTH/HEIGHT/CTRL while BUSY are dropped
--          (responded OKAY, not applied).
--
--          WIDTH/HEIGHT writes are clamped to the core's rule (out-of-range
--          values become the MAX generic), so a readback always returns the
--          value the core will actually use.
--
--------------------------------------------------------------------------------------------
-- REGISTER MAP (word-aligned offsets, 32-bit)
--------------------------------------------------------------------------------------------
--
--   0x00  ID       RO  ASCII "OJLS" (0x4F4A4C53)
--   0x04  VERSION  RO  0x00MMmmpp (major/minor/patch)
--   0x08  CAPS     RO  [7:0] BITNESS, [15:8] output bytes per beat (OUT_WIDTH/8)
--   0x0C  MAXDIM   RO  [15:0] MAX_IMAGE_WIDTH, [31:16] MAX_IMAGE_HEIGHT
--   0x10  WIDTH    RW  [15:0] image width  (clamped on write)
--   0x14  HEIGHT   RW  [15:0] image height (clamped on write)
--   0x18  CTRL     WO  [0] APPLY — self-clearing, pulses the core reset
--   0x1C  STATUS   RO  [0] BUSY (reset pulse active), [1] S_AXIS_TREADY mirror
--
-------------------------------------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.openjls_pkg.all;

-- AXI port names must keep the s_axi_*/s_axis_*/m_axis_* convention
-- (lowercase, underscores) for Vivado IP integrator interface inference.
-- vsg_off port_010 port_map_002

entity openjls_axi is
  generic (
    BITNESS          : positive range 8 to 16    := 12;
    MAX_IMAGE_WIDTH  : positive range 4 to 65535 := 4096;
    MAX_IMAGE_HEIGHT : positive range 1 to 65535 := 4096;
    OUT_WIDTH        : positive range 48 to 1024 := CO_OUT_WIDTH_STD;
    RESET_CYCLES     : positive                  := 16
  );
  port (
    aclk             : in    std_logic;
    aresetn          : in    std_logic;
    -- AXI4-Lite slave — configuration and status
    s_axi_awaddr     : in    std_logic_vector(7 downto 0);
    s_axi_awprot     : in    std_logic_vector(2 downto 0);
    s_axi_awvalid    : in    std_logic;
    s_axi_awready    : out   std_logic;
    s_axi_wdata      : in    std_logic_vector(31 downto 0);
    s_axi_wstrb      : in    std_logic_vector(3 downto 0);
    s_axi_wvalid     : in    std_logic;
    s_axi_wready     : out   std_logic;
    s_axi_bresp      : out   std_logic_vector(1 downto 0);
    s_axi_bvalid     : out   std_logic;
    s_axi_bready     : in    std_logic;
    s_axi_araddr     : in    std_logic_vector(7 downto 0);
    s_axi_arprot     : in    std_logic_vector(2 downto 0);
    s_axi_arvalid    : in    std_logic;
    s_axi_arready    : out   std_logic;
    s_axi_rdata      : out   std_logic_vector(31 downto 0);
    s_axi_rresp      : out   std_logic_vector(1 downto 0);
    s_axi_rvalid     : out   std_logic;
    s_axi_rready     : in    std_logic;
    -- AXI4-Stream slave — one pixel per beat, right-justified
    s_axis_tdata     : in    std_logic_vector(8 * ((BITNESS + 7) / 8) - 1 downto 0);
    s_axis_tvalid    : in    std_logic;
    s_axis_tlast     : in    std_logic;
    s_axis_tready    : out   std_logic;
    -- AXI4-Stream master — encoded .jls byte stream
    m_axis_tdata     : out   std_logic_vector(OUT_WIDTH - 1 downto 0);
    m_axis_tkeep     : out   std_logic_vector(OUT_WIDTH / 8 - 1 downto 0);
    m_axis_tvalid    : out   std_logic;
    m_axis_tlast     : out   std_logic;
    m_axis_tready    : in    std_logic
  );

  -- Vivado IP integrator interface inference
  attribute x_interface_info                   : string;
  attribute x_interface_parameter              : string;
  attribute x_interface_info of aclk           : signal is "xilinx.com:signal:clock:1.0 aclk CLK";
  -- aresetn is auto-associated with aclk by Vivado (standard name/polarity)
  attribute x_interface_parameter of aclk      : signal is "ASSOCIATED_BUSIF s_axi:s_axis:m_axis";
  attribute x_interface_info of aresetn        : signal is "xilinx.com:signal:reset:1.0 aresetn RST";
  attribute x_interface_parameter of aresetn   : signal is "POLARITY ACTIVE_LOW";
end entity openjls_axi;

architecture rtl of openjls_axi is

  constant VERSION     : std_logic_vector(31 downto 0) := x"00010000"; -- 1.0.0

  -- Word-address decode (byte offset / 4)
  constant REG_ID      : natural := 0;
  constant REG_VERSION : natural := 1;
  constant REG_CAPS    : natural := 2;
  constant REG_MAXDIM  : natural := 3;
  constant REG_WIDTH   : natural := 4;
  constant REG_HEIGHT  : natural := 5;
  constant REG_CTRL    : natural := 6;
  constant REG_STATUS  : natural := 7;

  -- Configuration registers
  signal sWidth        : unsigned(15 downto 0);
  signal sHeight       : unsigned(15 downto 0);

  -- Reset controller
  signal sRstCnt       : natural range 0 to RESET_CYCLES;
  signal sSoftRst      : std_logic;
  signal sCoreRst      : std_logic;

  -- AXI-Lite handshake state (single outstanding transaction per channel)
  signal sWrHandshake  : std_logic;
  signal sRdHandshake  : std_logic;
  signal sBValid       : std_logic;
  signal sRValid       : std_logic;
  signal sRData        : std_logic_vector(31 downto 0);

  signal sReadyMirror  : std_logic;

  -- Merge an AXI-Lite write into the low 16 bits of a register, honoring
  -- WSTRB, then clamp to the core's sample-time rule (out-of-range -> MAX)
  -- so readback always reports the value the core will actually use.

  function merge_clamp_dim (
    vcur   : unsigned(15 downto 0);
    vwdata : std_logic_vector(31 downto 0);
    vwstrb : std_logic_vector(3 downto 0);
    vmindim : natural;
    vmaxdim : natural
  ) return unsigned is

    variable vNew : unsigned(15 downto 0);

  begin

    vNew := vcur;

    if (vwstrb(0) = '1') then
      vNew(7 downto 0) := unsigned(vwdata(7 downto 0));
    end if;

    if (vwstrb(1) = '1') then
      vNew(15 downto 8) := unsigned(vwdata(15 downto 8));
    end if;

    if (vNew < vmindim or vNew > vmaxdim) then
      vNew := to_unsigned(vmaxdim, vNew'length);
    end if;

    return vNew;

  end function merge_clamp_dim;

begin

  -------------------------------------------------------------------------------------------------------------
  -- AXI4-Lite WRITE CHANNEL
  -------------------------------------------------------------------------------------------------------------
  -- Address and data are accepted in the same cycle (ready waits for both
  -- valids — legal: ready may depend on valid, not vice versa). Single
  -- outstanding transaction; next one is accepted after BREADY.

  sWrHandshake <= '1' when s_axi_awvalid = '1' and s_axi_wvalid = '1' and sBValid = '0' else
                  '0';

  s_axi_awready <= sWrHandshake;
  s_axi_wready  <= sWrHandshake;
  s_axi_bresp   <= "00"; -- OKAY; RO/unmapped writes are silently dropped
  s_axi_bvalid  <= sBValid;

  p_axi_write : process (aclk) is

    variable vAddrWord : natural;

  begin

    if rising_edge(aclk) then
      if (aresetn = '0') then
        sBValid <= '0';
        sWidth  <= to_unsigned(MAX_IMAGE_WIDTH, sWidth'length);
        sHeight <= to_unsigned(MAX_IMAGE_HEIGHT, sHeight'length);
        sRstCnt <= 0;
      else
        -- Soft-reset pulse countdown
        if (sRstCnt > 0) then
          sRstCnt <= sRstCnt - 1;
        end if;

        if (sBValid = '1' and s_axi_bready = '1') then
          sBValid <= '0';
        end if;

        if (sWrHandshake = '1') then
          sBValid   <= '1';
          vAddrWord := to_integer(unsigned(s_axi_awaddr(7 downto 2)));

          -- Configuration writes are dropped while the reset pulse is live:
          -- the core is sampling these registers right now.
          if (sSoftRst = '0') then

            case vAddrWord is

              when REG_WIDTH =>

                sWidth <= merge_clamp_dim(sWidth, s_axi_wdata, s_axi_wstrb, CO_MIN_IMAGE_WIDTH, MAX_IMAGE_WIDTH);

              when REG_HEIGHT =>

                sHeight <= merge_clamp_dim(sHeight, s_axi_wdata, s_axi_wstrb, CO_MIN_IMAGE_HEIGHT, MAX_IMAGE_HEIGHT);

              when REG_CTRL =>

                if (s_axi_wstrb(0) = '1' and s_axi_wdata(0) = '1') then
                  sRstCnt <= RESET_CYCLES;
                end if;

              when others =>

                null; -- RO / unmapped: dropped

            end case;

          end if;
        end if;
      end if;
    end if;

  end process p_axi_write;

  -------------------------------------------------------------------------------------------------------------
  -- AXI4-Lite READ CHANNEL
  -------------------------------------------------------------------------------------------------------------

  sRdHandshake <= '1' when s_axi_arvalid = '1' and sRValid = '0' else
                  '0';

  s_axi_arready <= sRdHandshake;
  s_axi_rresp   <= "00"; -- OKAY; unmapped reads return zero
  s_axi_rvalid  <= sRValid;
  s_axi_rdata   <= sRData;

  p_axi_read : process (aclk) is

    variable vAddrWord : natural;

  begin

    if rising_edge(aclk) then
      if (aresetn = '0') then
        sRValid <= '0';
        sRData  <= (others => '0');
      else
        if (sRValid = '1' and s_axi_rready = '1') then
          sRValid <= '0';
        elsif (sRdHandshake = '1') then
          sRValid   <= '1';
          vAddrWord := to_integer(unsigned(s_axi_araddr(7 downto 2)));
          sRData    <= (others => '0');

          case vAddrWord is

            when REG_ID =>

              sRData <= x"4F4A4C53";                                                       -- "OJLS"

            when REG_VERSION =>

              sRData <= VERSION;

            when REG_CAPS =>

              sRData(7 downto 0)  <= std_logic_vector(to_unsigned(BITNESS, 8));
              sRData(15 downto 8) <= std_logic_vector(to_unsigned(OUT_WIDTH / 8, 8));

            when REG_MAXDIM =>

              sRData(15 downto 0)  <= std_logic_vector(to_unsigned(MAX_IMAGE_WIDTH, 16));
              sRData(31 downto 16) <= std_logic_vector(to_unsigned(MAX_IMAGE_HEIGHT, 16));

            when REG_WIDTH =>

              sRData(15 downto 0) <= std_logic_vector(sWidth);

            when REG_HEIGHT =>

              sRData(15 downto 0) <= std_logic_vector(sHeight);

            when REG_STATUS =>

              sRData(0) <= sSoftRst;
              sRData(1) <= sReadyMirror;

            when others =>

              -- REG_CTRL reads as zero (write-only), unmapped reads zero
              null;

          end case;

        end if;
      end if;
    end if;

  end process p_axi_read;

  -------------------------------------------------------------------------------------------------------------
  -- RESET CONTROLLER + CORE
  -------------------------------------------------------------------------------------------------------------

  sSoftRst <= '1' when sRstCnt > 0 else
              '0';
  sCoreRst <= (not aresetn) or sSoftRst;

  s_axis_tready <= sReadyMirror;

  u_openjls_axis : entity work.openjls_axis(rtl)
    generic map (
      BITNESS          => BITNESS,
      MAX_IMAGE_WIDTH  => MAX_IMAGE_WIDTH,
      MAX_IMAGE_HEIGHT => MAX_IMAGE_HEIGHT,
      OUT_WIDTH        => OUT_WIDTH
    )
    port map (
      iClk             => aclk,
      iRst             => sCoreRst,
      iImageWidth      => std_logic_vector(sWidth),
      iImageHeight     => std_logic_vector(sHeight),
      s_axis_tdata     => s_axis_tdata,
      s_axis_tvalid    => s_axis_tvalid,
      s_axis_tlast     => s_axis_tlast,
      s_axis_tready    => sReadyMirror,
      m_axis_tdata     => m_axis_tdata,
      m_axis_tkeep     => m_axis_tkeep,
      m_axis_tvalid    => m_axis_tvalid,
      m_axis_tlast     => m_axis_tlast,
      m_axis_tready    => m_axis_tready
    );

end architecture rtl;
