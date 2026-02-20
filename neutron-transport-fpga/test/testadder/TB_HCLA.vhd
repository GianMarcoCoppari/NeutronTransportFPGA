-- TB_HCLA.vhd
-- Testbench for HCLA (Handshaking Carry Lookahead Adder)
-- Gian Marco Coppari
-- 2026/01/29

LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;
USE WORK.CONFIG.ALL;

ENTITY TB_HCLA IS
END ENTITY TB_HCLA;

ARCHITECTURE behavior OF TB_HCLA IS
    
    -- Parameters
    CONSTANT BLOCKS_TB     : INTEGER := 2; -- Test small chain first (8 bits total if M_BLOCKSIZE=4)
    CONSTANT M_BLOCKSIZE_V : INTEGER := M_BLOCKSIZE; -- Assume defined in config
    CONSTANT DATA_WIDTH    : INTEGER := M_BLOCKSIZE_V * BLOCKS_TB;
    
    -- Component Declaration
    COMPONENT HCLA IS
        GENERIC (
            BLOCKS : INTEGER
        );
        PORT (
            CLK      : IN  STD_LOGIC;
            RST      : IN  STD_LOGIC;
            VALIDIN  : IN  STD_LOGIC;
            
            A        : IN  STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0);
            B        : IN  STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0);
            CIN      : IN  STD_LOGIC;
            
            VALIDOUT : OUT STD_LOGIC;
            SUM      : OUT STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0);
            COUT     : OUT STD_LOGIC;
            OVF      : OUT STD_LOGIC
        );
    END COMPONENT HCLA;

    -- Signals
    SIGNAL tb_CLK      : STD_LOGIC := '0';
    SIGNAL tb_RST      : STD_LOGIC := '1';
    SIGNAL tb_VALIDIN  : STD_LOGIC := '0';
    SIGNAL tb_A        : STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0) := (OTHERS => '0');
    SIGNAL tb_B        : STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0) := (OTHERS => '0');
    SIGNAL tb_CIN      : STD_LOGIC := '0';
    
    SIGNAL tb_VALIDOUT : STD_LOGIC;
    SIGNAL tb_SUM      : STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0);
    SIGNAL tb_COUT     : STD_LOGIC;
    SIGNAL tb_OVF      : STD_LOGIC;
    
    -- Verification signals (Pipelines for expected results)
    CONSTANT TOTAL_LATENCY : INTEGER := BLOCKS_TB * 3; 
    TYPE expected_res_t IS RECORD
        res_sum  : UNSIGNED(DATA_WIDTH - 1 DOWNTO 0);
        res_cout : STD_LOGIC;
    END RECORD;
    
    TYPE pipe_verif_t IS ARRAY (0 TO TOTAL_LATENCY) OF expected_res_t;
    SIGNAL expected_pipe : pipe_verif_t;
    
    CONSTANT CLK_PERIOD : TIME := 10 ns;

BEGIN

    -- Clock Generation
    tb_CLK <= NOT tb_CLK AFTER CLK_PERIOD/2;
    
    -- DUT Instantiation
    DUT: HCLA 
        GENERIC MAP (
            BLOCKS => BLOCKS_TB
        )
        PORT MAP (
            CLK      => tb_CLK,
            RST      => tb_RST,
            VALIDIN  => tb_VALIDIN,
            A        => tb_A,
            B        => tb_B,
            CIN      => tb_CIN,
            VALIDOUT => tb_VALIDOUT,
            SUM      => tb_SUM,
            COUT     => tb_COUT,
            OVF      => tb_OVF
        );
        
    -- Verification Process
    -- Calculates expected result immediately and stores it in a shift register
    -- matching the DUT latency path.
    VERIF_PROC: PROCESS(tb_CLK, tb_RST)
        VARIABLE v_a_uns, v_b_uns : UNSIGNED(DATA_WIDTH DOWNTO 0); -- 1 bit extra for carry
        VARIABLE v_sum_full : UNSIGNED(DATA_WIDTH DOWNTO 0);
    BEGIN
        IF tb_RST = '1' THEN
            -- Reset expected pipeline
            FOR i IN 0 TO TOTAL_LATENCY LOOP
                expected_pipe(i).res_sum  <= (OTHERS => '0');
                expected_pipe(i).res_cout <= '0';
            END LOOP;
        ELSIF RISING_EDGE(tb_CLK) THEN
            -- 1. Compute Expected (Golden Model)
            v_a_uns := RESIZE(UNSIGNED(tb_A), DATA_WIDTH + 1);
            v_b_uns := RESIZE(UNSIGNED(tb_B), DATA_WIDTH + 1);
            
            IF tb_CIN = '1' THEN
                v_sum_full := v_a_uns + v_b_uns + 1;
            ELSE
                v_sum_full := v_a_uns + v_b_uns;
            END IF;
            
            -- Push into pipeline at index 0
            expected_pipe(0).res_sum  <= v_sum_full(DATA_WIDTH - 1 DOWNTO 0);
            expected_pipe(0).res_cout <= v_sum_full(DATA_WIDTH);
            
            -- Shift Pipeline
            FOR i IN 1 TO TOTAL_LATENCY LOOP
                expected_pipe(i) <= expected_pipe(i-1);
            END LOOP;
            
            -- Check Output when Valid
            IF tb_VALIDOUT = '1' THEN
                ASSERT STD_LOGIC_VECTOR(expected_pipe(TOTAL_LATENCY).res_sum) = tb_SUM
                    REPORT "Mismatch in SUM! Expected: " & integer'image(to_integer(expected_pipe(TOTAL_LATENCY).res_sum)) & 
                           " Got: " & integer'image(to_integer(unsigned(tb_SUM)))
                    SEVERITY ERROR;
                    
                ASSERT expected_pipe(TOTAL_LATENCY).res_cout = tb_COUT
                    REPORT "Mismatch in COUT!"
                    SEVERITY ERROR;
            END IF;
        END IF;
    END PROCESS;

    -- Stimulus Process
    STIM_PROC: PROCESS
    BEGIN
        tb_RST <= '1';
        WAIT FOR CLK_PERIOD * 5;
        tb_RST <= '0';
        WAIT FOR CLK_PERIOD;
        
        -- Test 1: Simple Addition
        tb_VALIDIN <= '1';
        tb_A <= std_logic_vector(to_unsigned(5, DATA_WIDTH));
        tb_B <= std_logic_vector(to_unsigned(10, DATA_WIDTH));
        tb_CIN <= '0';
        WAIT FOR CLK_PERIOD;
        
        -- Test 2: Carry Prop
        tb_A <= (OTHERS => '1'); -- Max value
        tb_B <= (0 => '1', OTHERS => '0'); -- +1
        tb_CIN <= '0';
        WAIT FOR CLK_PERIOD;
        
        -- Test 3: Ripple through blocks
        -- Need enough inputs to verify propagation through multiple blocks
        tb_A <= (OTHERS => '0');
        tb_B <= (OTHERS => '0');
        tb_CIN <= '1';
        WAIT FOR CLK_PERIOD;
        
        -- Stop valid input
        tb_VALIDIN <= '0';
        WAIT FOR CLK_PERIOD * 20;
        
        ASSERT FALSE REPORT "Simulation Completed Successfully" SEVERITY NOTE;
        WAIT;
    END PROCESS;

END ARCHITECTURE behavior;
