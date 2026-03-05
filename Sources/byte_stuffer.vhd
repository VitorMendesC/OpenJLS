----------------------------------------------------------------------------------
-- Company:
-- Engineer:    Vitor Mendes Camilo
--
-- Create Date:
-- Module Name: byte_stuffer - Behavioral
-- Description:
--
-- Notes:
--              Per T.87: every 0xFF byte in the encoded bitstream must be
--              followed by a stuffed zero bit so that decoders can distinguish
--              data from markers (which are 0xFF followed by a non-zero byte).
--
--              The module sits downstream of A11_2_bit_packer. It accepts
--              IN_WIDTH-bit words, scans for 0xFF bytes, inserts a single '0'
--              bit after each one, and re-emits OUT_WIDTH-bit words.
--
--              Byte boundary tracking (sBytePos / sByteReg) persists across
--              word boundaries so that a byte spanning two input words is
--              detected correctly.
--
--              iFlush: when asserted, outputs whatever partial byte-aligned data
--                      remains in the buffer (1–OUT_WIDTH bits, zero-padded to
--                      the next byte boundary) as a single output word with
--                      oValidBytes indicating how many bytes are meaningful.
--                      Has no effect if the buffer is already empty.
--                      oReady is deasserted while iFlush is held.
--
-- Assumptions:
--              IN_WIDTH must be a multiple of 8.
--              BUFFER_WIDTH >= 2 * IN_WIDTH + IN_WIDTH / 8
--
----------------------------------------------------------------------------------
use work.Common.all;

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;

library openlogic_base;
use openlogic_base.olo_base_pkg_math.log2ceil;

entity byte_stuffer is
  generic (
    IN_WIDTH     : natural := CO_OUT_WIDTH_STD;
    OUT_WIDTH    : natural := CO_OUT_WIDTH_STD;
    BUFFER_WIDTH : natural := 2 * CO_OUT_WIDTH_STD + CO_OUT_WIDTH_STD / 8
  );
  port (
    iClk        : in  std_logic;
    iRst        : in  std_logic;
    iValid      : in  std_logic;
    iWord       : in  std_logic_vector(IN_WIDTH  - 1 downto 0);
    iFlush      : in  std_logic;
    oReady      : out std_logic;
    oWord       : out std_logic_vector(OUT_WIDTH - 1 downto 0);
    oWordValid  : out std_logic;
    oValidBytes : out unsigned(log2ceil(OUT_WIDTH / 8) downto 0);
    iReady      : in  std_logic
  );
end entity byte_stuffer;

architecture Behavioral of byte_stuffer is

  signal sBuffer          : std_logic_vector(BUFFER_WIDTH - 1 downto 0);
  signal sCount           : unsigned(log2ceil(BUFFER_WIDTH) downto 0);
  signal sByteReg         : std_logic_vector(7 downto 0); -- last 8 input bits (shift register for 0xFF detection)
  signal sBytePos         : unsigned(2 downto 0);         -- bits into current input byte (0-7)
  signal sWordValidBuffer : std_logic;
  signal sOutWordBuffer   : std_logic_vector(OUT_WIDTH - 1 downto 0);
  signal sValidBytes      : unsigned(log2ceil(OUT_WIDTH / 8) downto 0);
  signal sAxiHandshake    : boolean;

begin

  assert IN_WIDTH mod 8 = 0
    report "byte_stuffer: IN_WIDTH must be a multiple of 8"
    severity failure;

  assert BUFFER_WIDTH >= 2 * IN_WIDTH + IN_WIDTH / 8
    report "byte_stuffer: BUFFER_WIDTH too small for worst-case stuffing expansion"
    severity failure;

  sAxiHandshake <= (iReady and sWordValidBuffer) = '1';

  oWordValid  <= sWordValidBuffer;
  oWord       <= sOutWordBuffer;
  oValidBytes <= sValidBytes;

  -- Accept a new word only when the buffer has room for the worst-case expansion and not flushing
  oReady <= '1' when to_integer(sCount) + IN_WIDTH + IN_WIDTH / 8 <= BUFFER_WIDTH
                     and iFlush = '0' else '0';

  process (iClk)
    variable vBuf        : std_logic_vector(BUFFER_WIDTH - 1 downto 0);
    variable vCount      : natural;
    variable vByteReg    : std_logic_vector(7 downto 0);
    variable vBPos       : natural range 0 to 8;
    variable vValidBytes : natural range 0 to OUT_WIDTH / 8;
  begin

    if rising_edge(iClk) then

      if iRst = '1' then
        sBuffer          <= (others => '0');
        sCount           <= (others => '0');
        sByteReg         <= (others => '0');
        sBytePos         <= (others => '0');
        sWordValidBuffer <= '0';
        sOutWordBuffer   <= (others => '0');
        sValidBytes      <= (others => '0');

      else

        vBuf     := sBuffer;
        vCount   := to_integer(sCount);
        vByteReg := sByteReg;
        vBPos    := to_integer(sBytePos);

        ------------------------------------------------------------------------------------------------------------
        -- Input: expand incoming word, inserting a '0' stuffing bit after every 0xFF output byte
        ------------------------------------------------------------------------------------------------------------

        if iValid = '1' and iFlush = '0' and to_integer(sCount) + IN_WIDTH + IN_WIDTH / 8 <= BUFFER_WIDTH then
          for i in IN_WIDTH - 1 downto 0 loop
            -- Append data bit to buffer (MSB of valid data is at index BUFFER_WIDTH-1)
            vBuf(BUFFER_WIDTH - 1 - vCount) := iWord(i);
            vCount   := vCount + 1;
            -- Track the current output byte in a shift register (new bits enter at LSB)
            vByteReg := vByteReg(6 downto 0) & iWord(i);
            vBPos    := vBPos + 1;

            if vBPos = 8 then
              vBPos := 0;
              if vByteReg = "11111111" then
                -- Insert stuffed '0' bit immediately after the 0xFF byte
                vBuf(BUFFER_WIDTH - 1 - vCount) := '0';
                vCount := vCount + 1;
                -- Stuffed bit is not a data bit: byte position already reset above
              end if;
            end if;
          end loop;
        end if;

        ------------------------------------------------------------------------------------------------------------
        -- Output: emit OUT_WIDTH bits when available
        ------------------------------------------------------------------------------------------------------------

        if vCount >= OUT_WIDTH and (sAxiHandshake or sWordValidBuffer = '0') then
          -- Full word: emit OUT_WIDTH bits, shift buffer, report all bytes valid
          sOutWordBuffer   <= vBuf(BUFFER_WIDTH - 1 downto BUFFER_WIDTH - OUT_WIDTH);
          vBuf             := std_logic_vector(shift_left(unsigned(vBuf), OUT_WIDTH));
          vCount           := vCount - OUT_WIDTH;
          sWordValidBuffer <= '1';
          sValidBytes      <= to_unsigned(OUT_WIDTH / 8, sValidBytes'length);
        elsif iFlush = '1' and vCount > 0 and (sAxiHandshake or sWordValidBuffer = '0') then
          -- Flush: emit remaining bits zero-padded to the next byte boundary.
          -- Bits beyond vCount are already '0' (shift_left fills with zeros).
          vValidBytes      := math_ceil_div(vCount, 8);
          sOutWordBuffer   <= vBuf(BUFFER_WIDTH - 1 downto BUFFER_WIDTH - OUT_WIDTH);
          vCount           := 0;
          sWordValidBuffer <= '1';
          sValidBytes      <= to_unsigned(vValidBytes, sValidBytes'length);
        elsif sAxiHandshake then
          -- Downstream consumed the last word; nothing new to produce
          sWordValidBuffer <= '0';
        end if;

        sBuffer  <= vBuf;
        sCount   <= to_unsigned(vCount, sCount'length);
        sByteReg <= vByteReg;
        sBytePos <= to_unsigned(vBPos, sBytePos'length);

      end if;
    end if;
  end process;

end architecture Behavioral;
