LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE work.configopenmc.ALL;

ENTITY tb_transport IS
END tb_transport;

ARCHITECTURE behavior OF tb_transport IS 
    
    -- Component Declaration
    COMPONENT TransportFSM
    PORT(
        clk : IN  std_logic;
        rst : IN  std_logic;
        validin : IN  std_logic;
        particlein : IN  particle_t;
        validout : OUT  std_logic;
        particleout : OUT  particle_t
    );
    END COMPONENT;

    -- Signals
    signal clk : std_logic := '0';
    signal rst : std_logic := '0';
    signal valid_in : std_logic := '0';
    signal p_in : particle_t := EMPTYPARTICLE;
    
    signal valid_out : std_logic;
    signal p_out : particle_t;
    
    constant clk_period : time := 10 ns;

BEGIN
 
    -- Instantiate the Unit Under Test (UUT)
    uut: TransportFSM PORT MAP (
        clk => clk,
        rst => rst,
        validin => valid_in,
        particlein => p_in,
        validout => valid_out,
        particleout => p_out
    );

    -- Clock process definitions
    clk_process :process
    begin
        clk <= '0';
        wait for clk_period/2;
        clk <= '1';
        wait for clk_period/2;
    end process;
 

    -- Stimulus process
    stim_proc: process
    begin		
        -- hold reset state for 100 ns.
        rst <= '1';
        wait for 100 ns;	
        rst <= '0';
        wait for clk_period*2;

        -- ============================================================
        -- TEST 1: OP_INIT -> OP_ADVANCE (Semplificato)
        -- ============================================================
        p_in <= EMPTYPARTICLE;
        p_in.alive <= '1';
        p_in.nextop <= OP_INIT;
        valid_in <= '1';
        wait for clk_period; 
        
        valid_in <= '0'; -- Stop stimolo
        
        -- Verifica Output
        wait until falling_edge(clk) and valid_out = '1';
        assert p_out.nextop = OP_ADVANCE report "Err 1: INIT failed (Should go to ADVANCE)" severity failure;
        
        wait for clk_period*2; -- Pausa fra i test

        -- ============================================================
        -- TEST 2: REMOVED (Was XS_LOOKUP)
        -- ============================================================
        -- Il test XS è stato rimosso poichè lo stato è stato assorbito.

        -- ============================================================
        -- TEST 3: OP_ADVANCE (Leakage case)
        -- dist_col (100) > dist_bound (50) -> OP_TALLY (Leakage)
        -- ============================================================
        p_in <= EMPTYPARTICLE;
        p_in.alive <= '1';
        p_in.nextop <= OP_ADVANCE;
        p_in.dist_collision <= to_unsigned(100, length);
        p_in.dist_boundary  <= to_unsigned(50, length);
        valid_in <= '1';
        wait for clk_period;
        valid_in <= '0';

        wait until falling_edge(clk) and valid_out = '1';
        assert p_out.nextop = OP_TALLY report "Err 3: Leakage failed (Should be TALLY)" severity failure;

        wait for clk_period*2;

        -- ============================================================
        -- TEST 4: OP_ADVANCE (Collision case)
        -- dist_col (20) < dist_bound (50) -> OP_COLLISION
        -- ============================================================
        p_in <= EMPTYPARTICLE;
        p_in.alive <= '1';
        p_in.nextop <= OP_ADVANCE;
        p_in.dist_collision <= to_unsigned(20, length);
        p_in.dist_boundary  <= to_unsigned(50, length);
        valid_in <= '1';
        wait for clk_period;
        valid_in <= '0';

        wait until falling_edge(clk) and valid_out = '1';
        assert p_out.nextop = OP_COLLISION report "Err 4: Collision failed" severity failure;

        wait for clk_period*2;
        
        -- ============================================================
        -- TEST 5: OP_COLLISION -> Morta (OP_TALLY)
        -- ============================================================
        p_in <= EMPTYPARTICLE;
        p_in.alive <= '0'; -- Particella uccisa (assorbita)
        p_in.nextop <= OP_COLLISION;
        valid_in <= '1';
        wait for clk_period;
        valid_in <= '0';

        wait until falling_edge(clk) and valid_out = '1';
        assert p_out.nextop = OP_TALLY report "Err 5: Death failed" severity failure;

        report "TUTTI I TEST PASSATI CON SUCCESSO!";
        wait;
    end process;
END;
