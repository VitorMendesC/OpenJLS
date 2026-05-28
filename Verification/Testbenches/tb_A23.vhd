use work.common.all;

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use std.env.all;

entity tb_a23 is
end entity tb_a23;

architecture bench of tb_a23 is

  shared variable errCount : natural;

  procedure check (
    cond : boolean;
    msg  : string
  ) is
  begin

    if (not cond) then
      report msg
        severity error;
      errCount := errCount + 1;
    end if;

  end procedure check;

  constant A_WIDTH         : natural := CO_AQ_WIDTH_STD;
  constant N_WIDTH         : natural := CO_NQ_WIDTH_STD;
  constant ERR_W           : natural := CO_ERROR_VALUE_WIDTH_STD;
  constant RESET_V         : natural := CO_RESET_STD;

  signal iErr              : signed(ERR_W - 1 downto 0);
  signal iRI               : std_logic;
  signal iAq               : unsigned(A_WIDTH - 1 downto 0);
  signal iNq               : unsigned(N_WIDTH - 1 downto 0);
  signal iNn               : unsigned(N_WIDTH - 1 downto 0);

  signal oAq               : unsigned(A_WIDTH - 1 downto 0);
  signal oNq               : unsigned(N_WIDTH - 1 downto 0);
  signal oNn               : unsigned(N_WIDTH - 1 downto 0);

  -- Reference model using Mert 2018 Fig. 9 equivalent: A[Q] += abs(Errval) - RItype

  procedure model (
    errv  : integer;
    ri    : integer;
    aq    : integer;
    nq    : integer;
    nn    : integer;
    expa  : out integer;
    expn  : out integer;
    expnn : out integer
  ) is

    variable vA  : integer;
    variable vN  : integer;
    variable vNn : integer;

  begin

    vA  := aq;
    vN  := nq;
    vNn := nn;

    if (errv < 0) then
      vNn := vNn + 1;
    end if;

    vA := vA + abs(errv) - ri;

    if (vN = integer(RESET_V)) then
      vA  := vA / 2;
      vN  := vN / 2;
      vNn := vNn / 2;
    end if;

    vN := vN + 1;

    expA  := vA;
    expN  := vN;
    expNn := vNn;

  end procedure model;

  procedure check_case (
    errv,
    aq,
    nq,
    nn   : integer;
    ri   : std_logic;
    aq_o : unsigned;
    nq_o : unsigned;
    nn_o : unsigned
  ) is

    variable riI   : integer;
    variable expA  : integer;
    variable expN  : integer;
    variable expNn : integer;

  begin

    if (ri = '1') then
      riI := 1;
    else
      riI := 0;
    end if;

    model(errv, riI, aq, nq, nn, expA, expN, expNn);

    check(aq_o = to_unsigned(expA, aq_o'length),
          "A23 Aq mismatch exp=" & integer'image(expA) &
          " got=" & integer'image(to_integer(aq_o))
        );
    check(nq_o = to_unsigned(expN, nq_o'length),
          "A23 Nq mismatch exp=" & integer'image(expN) &
          " got=" & integer'image(to_integer(nq_o))
        );
    check(nn_o = to_unsigned(expNn, nn_o'length),
          "A23 Nn mismatch exp=" & integer'image(expNn) &
          " got=" & integer'image(to_integer(nn_o))
        );

  end procedure check_case;

begin

  dut : entity work.a23_run_interruption_update(behavioral)

    generic map (
      A_WIDTH     => A_WIDTH,
      N_WIDTH     => N_WIDTH,
      ERROR_WIDTH => ERR_W,
      RESET       => RESET_V
    )
    port map (
      iErrVal     => iErr,
      iRItype     => iRI,
      iAq         => iAq,
      iNq         => iNq,
      iNn         => iNn,
      oAq         => oAq,
      oNq         => oNq,
      oNn         => oNn
    );

  stim : process is
  begin

    -- Initial values (no defaults — set explicitly here)
    iErr <= (others => '0');
    iRI  <= '0';
    iAq  <= (others => '0');
    iNq  <= (others => '0');
    iNn  <= (others => '0');

    -- Test 1: Errval<0, RItype=0, N=RESET (triggers halving)
    iErr <= to_signed(-3, iErr'length);
    iRI  <= '0';
    iAq  <= to_unsigned(20, iAq'length);
    iNq  <= to_unsigned(RESET_V, iNq'length);
    iNn  <= to_unsigned(5, iNn'length);
    wait for 1 ns;
    check_case(-3, 20, RESET_V, 5, '0', oAq, oNq, oNn);

    -- Test 2: Errval>0, RItype=1
    iErr <= to_signed(4, iErr'length);
    iRI  <= '1';
    iAq  <= to_unsigned(50, iAq'length);
    iNq  <= to_unsigned(10, iNq'length);
    iNn  <= to_unsigned(2, iNn'length);
    wait for 1 ns;
    check_case(4, 50, 10, 2, '1', oAq, oNq, oNn);

    -- Test 3: Errval<0, RItype=1
    iErr <= to_signed(-1, iErr'length);
    iRI  <= '1';
    iAq  <= to_unsigned(100, iAq'length);
    iNq  <= to_unsigned(3, iNq'length);
    iNn  <= to_unsigned(1, iNn'length);
    wait for 1 ns;
    check_case(-1, 100, 3, 1, '1', oAq, oNq, oNn);

    -- Test 4: Errval>0, RItype=0, all zeros
    iErr <= to_signed(1, iErr'length);
    iRI  <= '0';
    iAq  <= to_unsigned(0, iAq'length);
    iNq  <= to_unsigned(0, iNq'length);
    iNn  <= to_unsigned(0, iNn'length);
    wait for 1 ns;
    check_case(1, 0, 0, 0, '0', oAq, oNq, oNn);

    if (errCount > 0) then
      report "tb_A23 RESULT: FAIL (" & integer'image(errCount) & " errors)"
        severity failure;
    else
      report "tb_A23 RESULT: PASS"
        severity note;
    end if;

    finish;

  end process stim;

end architecture bench;
