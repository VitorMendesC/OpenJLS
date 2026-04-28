----------------------------------------------------------------------------------
-- Engineer:    Vitor Mendes Camilo
--
-- Module Name: byte_stuffer - Behavioral
-- Description:
--
-- Notes:
--              Per T.87: every 0xFF byte in the encoded bitstream must be
--              followed by a stuffed zero bit so that decoders can distinguish
--              data from markers (0xFF followed by a non-zero byte).
--
--              Sits downstream of A11_2_bit_packer, which emits a variable-
--              length word per cycle: (iWord, iWordValid, iValidLen) — top
--              iValidLen bits of iWord are meaningful, MSB-first.
--
--              Byte_stuffer accumulates input bits, scans for 0xFF byte
--              boundaries, inserts a single '0' after each one, and emits
--              every complete byte the same cycle. Sub-byte residue (0..7
--              bits) carries to the next cycle. Output word is OUT_WIDTH bits
--              wide; oValidBytes (1..OUT_WIDTH/8) reports how many top bytes
--              are meaningful.
--
--              Byte boundary tracking (sBytePos / sByteReg) persists across
--              word boundaries so that a byte spanning two input words is
--              detected correctly.
--
--              iFlush: zero-pad the residue up to a byte boundary, emit the
--                      remaining bytes (full + padded), reset the byte
--                      tracker for the next image. Single-cycle pulse.
--                      Per the design contract, vCount at flush must fit in
--                      one OUT_WIDTH word (steady-state pipeline guarantees
--                      this — no downstream stall during flush).
--
-- Assumptions:
--              OUT_WIDTH must be a multiple of 8.
--              BUFFER_WIDTH >= IN_WIDTH + IN_WIDTH/8 + 7
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
    IN_WIDTH     : natural := CO_LIMIT_STD;
    OUT_WIDTH    : natural := math_ceil_div(CO_LIMIT_STD + CO_LIMIT_STD / 8 + 7, 8) * 8;
    BUFFER_WIDTH : natural := 2 * CO_LIMIT_STD + CO_LIMIT_STD / 8
  );
  port (
    iClk        : in std_logic;
    iRst        : in std_logic;
    iWord       : in std_logic_vector(IN_WIDTH - 1 downto 0);
    iWordValid  : in std_logic;
    iValidLen   : in unsigned(log2ceil(IN_WIDTH + 1) - 1 downto 0);
    iFlush      : in std_logic;
    oWord       : out std_logic_vector(OUT_WIDTH - 1 downto 0);
    oWordValid  : out std_logic;
    oValidBytes : out unsigned(log2ceil(OUT_WIDTH / 8 + 1) - 1 downto 0)
  );
end entity byte_stuffer;

architecture Behavioral of byte_stuffer is

  signal sBuffer          : std_logic_vector(BUFFER_WIDTH - 1 downto 0);
  signal sCount           : unsigned(log2ceil(BUFFER_WIDTH + 1) - 1 downto 0);
  signal sByteReg         : std_logic_vector(7 downto 0);
  signal sBytePos         : unsigned(2 downto 0);
  signal sWordValidBuffer : std_logic;
  signal sOutWordBuffer   : std_logic_vector(OUT_WIDTH - 1 downto 0);
  signal sValidBytes      : unsigned(log2ceil(OUT_WIDTH / 8 + 1) - 1 downto 0);

begin

  assert OUT_WIDTH mod 8 = 0
  report "byte_stuffer: OUT_WIDTH must be a multiple of 8"
    severity failure;

  assert BUFFER_WIDTH >= IN_WIDTH + math_ceil_div(IN_WIDTH, 8) + 7
  report "byte_stuffer: BUFFER_WIDTH too small for one-cycle worst case (residue + input + stuffing)"
    severity failure;

  assert OUT_WIDTH >= math_ceil_div(IN_WIDTH + math_ceil_div(IN_WIDTH, 8) + 7, 8) * 8
  report "byte_stuffer: OUT_WIDTH too small to drain worst-case input in one cycle (residue invariant)"
    severity failure;

  -- Comb. output
  oWordValid  <= sWordValidBuffer;
  oWord       <= sOutWordBuffer;
  oValidBytes <= sValidBytes;

  -------------------------------------------------------------------------------------------------------------------------
  -- SYNCHRONOUS PROCESS 
  -------------------------------------------------------------------------------------------------------------------------
  sync_proc : process (iClk)
    variable vBuf         : std_logic_vector(BUFFER_WIDTH - 1 downto 0);
    variable vCountInt    : natural;
    variable vByteReg     : std_logic_vector(7 downto 0);
    variable vBytePosInt  : natural range 0 to 8;
    variable vBytesOut    : natural;
    variable vValidLenInt : natural;
    variable vBitVal      : std_logic;
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

        vBuf         := sBuffer;
        vCountInt    := to_integer(sCount);
        vByteReg     := sByteReg;
        vBytePosInt  := to_integer(sBytePos);
        vValidLenInt := to_integer(iValidLen);

        ------------------------------------------------------------------------------------------------------------
        -- Input: append top vValidLen bits of iWord (MSB-first), inserting a '0'
        -- stuffing bit after every completed 0xFF byte.
        ------------------------------------------------------------------------------------------------------------

        if iWordValid = '1' then
          for i in 0 to IN_WIDTH - 1 loop
            if i < vValidLenInt then
              vBitVal                            := iWord(IN_WIDTH - 1 - i);
              vBuf(BUFFER_WIDTH - 1 - vCountInt) := vBitVal;
              vCountInt                          := vCountInt + 1;
              vByteReg                           := vByteReg(6 downto 0) & vBitVal;
              vBytePosInt                        := vBytePosInt + 1;

              if vBytePosInt = 8 then
                vBytePosInt := 0;
                if vByteReg = "11111111" then
                  vBuf(BUFFER_WIDTH - 1 - vCountInt) := '0';
                  vCountInt                          := vCountInt + 1;
                  vByteReg                           := vByteReg(6 downto 0) & '0'; -- accounts for the stuffed bit in the byte tracker
                  vBytePosInt                        := 1;
                end if;
              end if;
            end if;
          end loop;
        end if;

        ------------------------------------------------------------------------------------------------------------
        -- Output: emit complete bytes (variable count). On iFlush, also drain
        -- the sub-byte residue zero-padded to the next byte boundary and reset
        -- the byte tracker so the next image starts on a fresh boundary.
        ------------------------------------------------------------------------------------------------------------

        if iFlush = '1' and vCountInt > 0 then
          vBytesOut := math_ceil_div(vCountInt, 8);
          sOutWordBuffer   <= vBuf(BUFFER_WIDTH - 1 downto BUFFER_WIDTH - OUT_WIDTH);
          sValidBytes      <= to_unsigned(vBytesOut, sValidBytes'length);
          sWordValidBuffer <= '1';
          vBuf        := std_logic_vector(shift_left(unsigned(vBuf), vBytesOut * 8));
          vCountInt   := 0;
          vBytePosInt := 0;
          vByteReg    := (others => '0');

        elsif vCountInt >= 8 then

          vBytesOut := vCountInt / 8;
          if vBytesOut > OUT_WIDTH / 8 then
            vBytesOut := OUT_WIDTH / 8;
          end if;

          sOutWordBuffer   <= vBuf(BUFFER_WIDTH - 1 downto BUFFER_WIDTH - OUT_WIDTH);
          sValidBytes      <= to_unsigned(vBytesOut, sValidBytes'length);
          sWordValidBuffer <= '1';
          vBuf      := std_logic_vector(shift_left(unsigned(vBuf), vBytesOut * 8));
          vCountInt := vCountInt - vBytesOut * 8;

        else
          sWordValidBuffer <= '0';
        end if;

        -- Registers
        sBuffer  <= vBuf;
        sCount   <= to_unsigned(vCountInt, sCount'length);
        sByteReg <= vByteReg;
        sBytePos <= to_unsigned(vBytePosInt, sBytePos'length);

      end if;
    end if;
  end process sync_proc;

end architecture Behavioral;
