library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use ieee.std_logic_textio.all;
use work.config.all;
use work.configcordich.all;
use work.configopenmc.all;
use work.xs_rom_small.all;

----------------------------------------------------------------------------------
-- Entity: physicsworker
-- Description:
--   Calculates the distance to next collision (dist_collision) for a particle.
--   
-- Formula:
--   d_collision = -ln(rn) / Sigma_total of material
--   Rewrite: d_collision = -ln(rn) * (1 / Sigma_total)
--   
-- Components:
--   1. PRNG (Xoshiro256**): Generates uniform random number 'r'.
--   2. CORDIC Ln: Calculates -ln(r). Note: Ln of fractions < 1 is negative, so -ln is positive.
--   3. Cross Section Lookup: Uses 'xs' package to fetch (1/Sigma) constant.
--   4. Multiplier: Performs multiplication -ln(r) * (1/Sigma).
--
-- Note:
--   This module replaces the deprecated division-based approach (d = -ln(r) / Sum_Sigma)
--   with a multiplication approach for higher throughput.
----------------------------------------------------------------------------------
entity physicsworker is
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;
        
        -- Input from Input Queue/Router
        p_in       : in  particle_t;
        p_in_valid : in  std_logic;
        
        -- Output to Arbiter / Transport Kernel
        p_out      : out particle_t;
        p_out_valid: out std_logic
    );
end physicsworker;

architecture behavioral of physicsworker is
    
    -- Helper function to safely convert ID to integer for logging
    -- Handles large IDs by taking only lower bits that fit in integer range
    function safe_id_to_int(id_vec : std_logic_vector) return integer is
        variable v_low_bits : unsigned(30 downto 0);
    begin
        if id_vec'length >= 31 then
            v_low_bits := unsigned(id_vec(30 downto 0));
        else
            v_low_bits := resize(unsigned(id_vec), 31);
        end if;
        return to_integer(v_low_bits);
    end function;
    
    -- =========================================================================
    -- CONSTANTS & LATENCY
    -- =========================================================================
    -- Calcolo latenze per le linee di ritardo (Shift Register)
    -- customln: 1 (input reg) + m_maxiterh (stages) for CORDIC hyperbolic
    constant LATENCY_LN  : integer := m_maxiterh + 1;
    -- XS Lookup Latency (Dynamic based on ROM size)
    -- Latency = Binary Search + ROM Fetch + Linear Interpolation
    -- Binary search: log2(ROM_SIZE) stages
    -- ROM Fetch: 1 stage
    -- Linear interpolation (lspline): 69 stages (divr2 64 + overhead)
    constant STAGES_XS   : integer := log2_ceil(ROM_ENERGY'length);
    constant LATENCY_INTERP : integer := 69; -- lspline latency with divr2
    constant LATENCY_XS  : integer := STAGES_XS + 1 + LATENCY_INTERP; -- ~77 cycles for ROM_SIZE=64
    -- Since XS is slower than LN, we delay LN output instead
    constant DELAY_LN    : integer := LATENCY_XS - LATENCY_LN; -- Delay for neg_ln_out
    
    -- Multiplier (Registered):
    -- Clock 0: Input Latch
    -- Clock 1: Product valid in 'mult_prod' signal
    -- Clock 2: Output valid in 'p_out' (requires reading mult_prod)
    constant LATENCY_MULT : integer := 2; -- AUMENTATO DA 1 A 2 PER FIX PIPELINE
    
    -- =========================================================================
    -- SIGNALS
    -- =========================================================================
    
    -- RNG
    signal rng_val      : unsigned(length-1 downto 0);
    
    -- Logarithm
    signal ln_in        : signed(length-1 downto 0);
    signal ln_out       : signed(length-1 downto 0);
    signal neg_ln_out   : unsigned(length-1 downto 0); -- -ln(rng) cast to unsigned
    
    -- Multiplier
    signal mult_op1     : unsigned(length-1 downto 0);
    signal mult_op2     : unsigned(length-1 downto 0);
    signal mult_prod    : unsigned(2*length-1 downto 0); -- 128 bit
    signal dist_result  : unsigned(length-1 downto 0);
    
    -- Pipeline for mult_prod to align with particle pipeline
    type mult_prod_pipe_t is array (0 to LATENCY_MULT) of unsigned(2*length-1 downto 0);
    signal mult_prod_pipe : mult_prod_pipe_t;
    
    -- Delay Pipelines (Shift Registers)
    type p_delay_array_ln is array (0 to LATENCY_LN) of particle_t;
    signal p_pipe_ln : p_delay_array_ln;

    -- Add RNG Pipeline for Debug traceability
    type rng_delay_array_ln is array (0 to LATENCY_LN) of unsigned(length-1 downto 0);
    signal rng_pipe_ln : rng_delay_array_ln;
    
    type rng_delay_array_mult is array (0 to LATENCY_MULT) of unsigned(length-1 downto 0);
    signal rng_pipe_mult : rng_delay_array_mult;

    type p_delay_array_mult is array (0 to LATENCY_MULT) of particle_t;
    signal p_pipe_mult : p_delay_array_mult;
    
    type val_delay_array_mult is array (0 to LATENCY_MULT) of std_logic;
    signal val_pipe_mult : val_delay_array_mult;
    
    -- Stage 0 Signals
    signal s0_p         : particle_t;
    signal s0_valid     : std_logic;
    signal s0_ln_in     : signed(length-1 downto 0); -- Alignment register

    -- XS Lookup Signals
    signal xs_inv_sigma_raw : unsigned(length-1 downto 0);
    signal xs_valid_raw     : std_logic;

    -- Pipeline Declarations for LN delay
    type delay_array_unsigned_t is array (0 to DELAY_LN) of unsigned(length-1 downto 0);
    signal neg_ln_delayed : delay_array_unsigned_t;
    type delay_array_valid_t is array (0 to DELAY_LN) of std_logic;
    signal valid_ln_delayed : delay_array_valid_t;
    
    -- Extended particle pipeline to match XS latency
    type pipe_xs_t is array (0 to DELAY_LN) of particle_t;
    signal p_pipe_xs      : pipe_xs_t;
    type val_delay_xs is array (0 to DELAY_LN) of std_logic;
    signal val_pipe_xs    : val_delay_xs;
    type rng_pipe_xs_array_t is array (0 to DELAY_LN) of unsigned(length-1 downto 0);
    signal rng_pipe_xs    : rng_pipe_xs_array_t;
    
    -- Pipeline for XS values (propagate XS output through DELAY_LN stages)
    signal xs_inv_sigma_pipe : delay_array_unsigned_t;
    signal valid_xs_pipe : delay_array_valid_t;

    type val_delay_array_ln is array (0 to LATENCY_LN) of std_logic;
    signal val_pipe_ln : val_delay_array_ln;

BEGIN
    
    -- =========================================================================
    -- 1. INSTANCES
    -- =========================================================================
    
    -- XS Lookup Instance
    inst_xslookup : entity work.xs_lookup
        port map (
            clk => clk,
            rst => rst,
            energy_in => s0_p.energy, -- Use registered energy (T1)
            valid_in  => s0_valid,    -- Start lookup at T1
            inv_sigma_out => xs_inv_sigma_raw,
            valid_out     => xs_valid_raw
        );

    -- =========================================================================
    -- 1. INSTANCES (Continued)
    -- =========================================================================
    
    -- RNG: Genera numeri casuali continui
    instprng : entity work.xoshiro256
        port map (
            clk      => clk,
            rst      => rst,
            rnd      => rng_val
        );

    -- Prepara Input Logaritmo (Mapping RNG -> Fixed Point Q16.48 in range [0,1))
    -- RNG è 64 bit full scale. 
    -- Q16.48 ha 48 bit frazionari.
    -- Prendiamo i 48 bit alti dell'RNG e li mettiamo nella parte frazionaria.
    -- win = 000...000 & rng(63 downto 16)
    ln_in <= signed(resize(rng_val(length-1 downto 16), length));

    -- Custom Logarithm: Calcola ln(w)
    instln : entity work.customln
        port map (
            clk   => clk,
            rst   => rst,
            win   => s0_ln_in,
            lnout => ln_out
        );
        
    -- Gestione Segno Logaritmo
    -- customln already outputs -ln(x) as a positive value (negation done inside).
    -- We just cast to unsigned for the multiplier.
    neg_ln_out <= unsigned(ln_out);

    -- =========================================================================
    -- 2. PIPELINE CONTROL & DELAY LOGIC
    -- =========================================================================
    -- begin
    --     if rising_edge(clk) then
    --         if val_pipe_ln(LATENCY_LN - 1) = '1' then
    --             report "DEBUG: LN_OUT=" & to_hstring(ln_out) & 
    --                    " NEG_LN=" & to_hstring(neg_ln_out) & 
    --                    " DIVIDEND=" & to_hstring(div_dividend) &
    --                    " DIVISOR=" & to_hstring(div_divisor);
    --         end if;
    --     end if;
    -- end process;

    -- =========================================================================
    -- 2. PIPELINE CONTROL & DELAY LOGIC
    -- =========================================================================
    
    -- Connection of Multiplier Operands (Combinatorial)
    -- Use pipelined XS value that aligns with delayed LN
    mult_op2 <= xs_inv_sigma_pipe(DELAY_LN);
    mult_op1 <= neg_ln_delayed(DELAY_LN);

    PROCESS(clk, rst)
        variable v_line        : line;
        variable v_out_particle : particle_t;
    BEGIN
        if rst = '1' then
            -- ASYNCHRONOUS RESET: Ensures defined state at T=0
            s0_valid <= '0';
            p_out_valid <= '0';
            
            -- Reset data signals to safe values
            s0_p     <= EMPTYPARTICLE;
            s0_ln_in <= (others => '0');
            
            -- Flush pipelines
            val_pipe_ln   <= (others => '0');
            neg_ln_delayed <= (others => (others => '0'));
            valid_ln_delayed <= (others => '0');
            xs_inv_sigma_pipe <= (others => (others => '0'));
            valid_xs_pipe <= (others => '0');
            p_pipe_ln     <= (others => EMPTYPARTICLE);
            rng_pipe_ln   <= (others => (others => '0'));
            
            val_pipe_xs   <= (others => '0');
            p_pipe_xs     <= (others => EMPTYPARTICLE);
            rng_pipe_xs   <= (others => (others => '0'));
            
            val_pipe_mult <= (others => '0');
            p_pipe_mult   <= (others => EMPTYPARTICLE);
            rng_pipe_mult <= (others => (others => '0'));
            
            mult_prod <= (others => '0');
            mult_prod_pipe <= (others => (others => '0'));
            dist_result <= (others => '0');
            p_out <= EMPTYPARTICLE;
            p_out.dist_collision <= (others => '0');
            
        elsif rising_edge(clk) then
            -- STAGE 0: Lookup & Launch
            if p_in_valid = '1' then 
                rng_pipe_ln(0) <= rng_val; -- Capture RNG for pipeline tracking
                
                s0_valid <= '1';
                s0_p     <= p_in;
                
                s0_ln_in <= ln_in; -- Sample Input at same time as valid
            else
                s0_valid <= '0';
                rng_pipe_ln(0) <= (others => '0');
                -- Keep s0_ln_in at last valid value (don't clear to 0)
                -- This ensures the CORDIC pipeline is filled with the correct
                -- -ln(rng) value, compensating for any valid-signal alignment offset.
            end if;
            
            -- SHIFT REGISTER 1: Delay durante calcolo LN
            p_pipe_ln(0)         <= s0_p;
            val_pipe_ln(0)       <= s0_valid;
            
            for i in 0 to LATENCY_LN - 1 loop
                p_pipe_ln(i+1)     <= p_pipe_ln(i);
                val_pipe_ln(i+1)   <= val_pipe_ln(i);
                rng_pipe_ln(i+1)   <= rng_pipe_ln(i); -- Propagate RNG
            end loop;

            -- DELAY LINE FOR LN RESULT (to align with XS)
            -- Propagate LN value with its valid signal
            neg_ln_delayed(0) <= neg_ln_out;
            valid_ln_delayed(0) <= val_pipe_ln(LATENCY_LN);
            for i in 0 to DELAY_LN - 1 loop
                 neg_ln_delayed(i+1) <= neg_ln_delayed(i);
                 valid_ln_delayed(i+1) <= valid_ln_delayed(i);
            end loop;
            
            -- PIPELINE FOR XS RESULT
            -- Propagate XS value with its valid signal
            xs_inv_sigma_pipe(0) <= xs_inv_sigma_raw;
            valid_xs_pipe(0) <= xs_valid_raw;
            for i in 0 to DELAY_LN - 1 loop
                xs_inv_sigma_pipe(i+1) <= xs_inv_sigma_pipe(i);
                valid_xs_pipe(i+1) <= valid_xs_pipe(i);
            end loop;
            
            -- EXTENDED PARTICLE PIPELINE (from LN to XS completion)
            p_pipe_xs(0)   <= p_pipe_ln(LATENCY_LN);
            val_pipe_xs(0) <= val_pipe_ln(LATENCY_LN);
            rng_pipe_xs(0) <= rng_pipe_ln(LATENCY_LN);
            
            for i in 0 to DELAY_LN - 1 loop
                p_pipe_xs(i+1)   <= p_pipe_xs(i);
                val_pipe_xs(i+1) <= val_pipe_xs(i);
                rng_pipe_xs(i+1) <= rng_pipe_xs(i);
            end loop;
            
            -- STAGE 2: Multiplication (Registered)
            -- Input comes from end of longer pipeline (XS)
            -- mult_op1 (delayed LN) and mult_op2 (XS) are now aligned
            
            -- Compute multiplication directly into pipeline (combinatorial inputs, registered output)
            mult_prod_pipe(0) <= mult_op1 * mult_op2;
            mult_prod <= mult_prod_pipe(0); -- Keep mult_prod for backward compatibility

            -- Pipeline for Mult Latency (use XS timing since it's the limiting path)
            p_pipe_mult(0)   <= p_pipe_xs(DELAY_LN);
            val_pipe_mult(0) <= valid_xs_pipe(DELAY_LN); -- Use delayed XS valid signal for proper alignment
            rng_pipe_mult(0) <= rng_pipe_xs(DELAY_LN);
            
            for i in 0 to LATENCY_MULT - 1 loop
                p_pipe_mult(i+1)   <= p_pipe_mult(i);
                val_pipe_mult(i+1) <= val_pipe_mult(i);
                rng_pipe_mult(i+1) <= rng_pipe_mult(i);
                mult_prod_pipe(i+1) <= mult_prod_pipe(i); -- Propagate mult result
            end loop;
            -- FINAL STAGE: Collect Result
            -- Logic Analysis for Alignment:
            -- Cycle T0: Process Input. mult_op1/2 set up.
            -- Cycle T1: "mult_prod" register updates (Result of T0).
            --           "p_pipe_mult(0)" register updates (Data of T0).
            --           We read these values NOW to drive p_out.
            --           p_out <= p_pipe_mult(0) with dist overrided by mult_prod.
            -- Cycle T2: "p_out" register updates (Result of T1). Ready for output.
            
            -- Use variable to properly override dist_collision field
            v_out_particle := p_pipe_mult(LATENCY_MULT);
            v_out_particle.dist_collision := mult_prod_pipe(LATENCY_MULT)(111 downto 48);
            p_out <= v_out_particle;
            
            -- Valid Output Logic
            p_out_valid <= val_pipe_mult(LATENCY_MULT);

            -- Debug Print: Distance Output
            if val_pipe_mult(LATENCY_MULT) = '1' then
                write(v_line, string'("Advancement, Id: "));
                write(v_line, safe_id_to_int(p_pipe_mult(LATENCY_MULT).id));
                write(v_line, string'(" dist: "));
                hwrite(v_line, mult_prod_pipe(LATENCY_MULT)(111 downto 48));
                writeline(output, v_line);
            end if;
        
        end if;
    end process;

end architecture behavioral;
