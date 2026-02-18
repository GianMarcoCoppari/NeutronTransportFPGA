LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;
use work.config.all;
USE work.configopenmc.ALL;


ENTITY advanceworker IS
    PORT (
        clk         : IN  STD_LOGIC;
        rst         : IN  STD_LOGIC;
        
        -- Input: Particella da processare (Stato ADVANCE)
        p_in          : IN  particle_t;
        p_in_valid    : IN  STD_LOGIC;
        
        -- Output: Particella aggiornata (Nuova posizione, distanze calcolate)
        p_out         : OUT particle_t;
        p_out_valid   : OUT STD_LOGIC;
        
        -- Segnale di Backpressure (semplificato)
        ready         : OUT STD_LOGIC
    );
END advanceworker;

ARCHITECTURE Behavioral OF advanceworker IS

    -- =========================================================================
    -- CONFIGURAZIONE
    -- =========================================================================
    -- Le costanti BOX_LIMIT etc sono ora nei sotto-moduli
    
    -- =========================================================================
    -- SEGNALI INTERNI
    -- =========================================================================
    signal w_rng_val    : unsigned(63 downto 0);
    signal w_dist_coll  : unsigned(length-1 downto 0);
    signal w_dist_bound : unsigned(length-1 downto 0);

BEGIN

    -- Ready sempre alto
    ready <= '1'; 

    -- =========================================================================
    -- 1. INSTANCE CUSTOM RNG
    -- =========================================================================
    Inst_RNG: entity work.xoshiro256
    PORT MAP (
        clk => clk,
        rst => rst,
        
        rnd => w_rng_val
    );

    -- =========================================================================
    -- 2. INSTANCE PHYSICS (Collision Distance)
    -- =========================================================================
    Inst_Physics: entity work.CalcDistPhysics
    PORT MAP (
        clk => clk,
        rst => rst,
        material  => p_in.material,
        rng_val   => w_rng_val, -- Connected to CustomRNG
        dist_coll => w_dist_coll
    );

    -- =========================================================================
    -- 3. INSTANCE GEOMETRY (Boundary Distance)
    -- =========================================================================
    Inst_Geometry: entity work.CalcDistGeometry
    PORT MAP (
        clk => clk,
        rst => rst,
        position   => p_in.position,
        direction  => p_in.direction,
        dist_bound => w_dist_bound
    );


    -- =========================================================================
    -- 4. MOVIMENTO E OUTPUT REGISTRATION
    -- =========================================================================
    process(clk, rst)
        variable v_p_in      : particle_t;
        variable v_dist_min  : unsigned(length-1 downto 0);
    begin
        if rst = '1' then
            p_out_valid <= '0';
            p_out <= EMPTYPARTICLE;
            
        elsif rising_edge(clk) then
        
            p_out_valid <= '0'; -- Pulse default
            
            if p_in_valid = '1' then
                v_p_in := p_in;
                
                -- Salva le distanze calcolate dai sottomoduli (Combinatorial Input -> Output)
                v_p_in.dist_collision := w_dist_coll;
                v_p_in.dist_boundary  := w_dist_bound;

                -- Scegli distanza minima
                if w_dist_coll < w_dist_bound then
                    v_dist_min := w_dist_coll;
                else
                    v_dist_min := w_dist_bound;
                end if;
                
                -- Aggiorna Posizione: P' = P + V * d
                v_p_in.position.x := v_p_in.position.x + resize(v_p_in.direction.vx * signed(v_dist_min), length);
                v_p_in.position.y := v_p_in.position.y + resize(v_p_in.direction.vy * signed(v_dist_min), length);
                v_p_in.position.z := v_p_in.position.z + resize(v_p_in.direction.vz * signed(v_dist_min), length);
                
                -- Output
                p_out      <= v_p_in;
                p_out_valid <= '1';
                
            end if; -- valid_in
        end if; -- clk/rst
    end process;

END Behavioral;