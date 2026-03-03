library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use ieee.std_logic_textio.all;
use work.config.all;
use work.configopenmc.all;

--------------------------------------------------------------------------------
-- Entity: eventworker
-- Description: 
--   Gestisce l'evento post-trasporto.
--   Accetta particelle che hanno completato uno step di geometria (COLLISION o SURFACE).
--
-- Logic Flow:
--   1. SURFACE CROSSING:
--      - Controlla tipo di superficie (Vacuum vs Reflective).
--      - Se Vacuum -> Kill (Finished).
--
--   2. COLLISION:
--      - Lancia il prob_lookup per ottenere P_abs(E), P_fiss(E) dalle tabelle nucleari.
--      - Quando il lookup completa (~77 cicli), usa il PRNG per decidere:
--        Absorption / Fission / Scattering.
--      - Lancia il kernel appropriato.
--
-- Changes:
--   - Probabilita' di interazione derivate dalle tabelle di sezioni d'urto 
--     (ROM_PROB_ABSORPTION, ROM_PROB_FISSION) tramite prob_lookup energy-dependent.
--   - Rimosso uso di costanti hardcoded (PROB_ABS_FUEL, PROB_FISS_FUEL).
--------------------------------------------------------------------------------
entity eventworker is
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;
        
        -- Input dalla Pipeline (Geometry/Transport)
        valid_in    : in  std_logic;
        particle_in : in  particle_t;
        
        -- Output verso Scheduler/FIFO
        valid_out   : out std_logic;
        particle_out: out particle_t;
        
        -- Backpressure
        busy        : out std_logic
    );
end entity eventworker;

architecture behavioral of eventworker is

    -- Helper function to safely convert ID to integer for logging
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

    -- Componenti Fisica
    component absorption is
        port (
            clk, rst : in std_logic;
            start : in std_logic;
            particle_in : in particle_t;
            done : out std_logic;
            particle_out : out particle_t
        );
    end component;

    component scattering_realistic is
        port (
            clk, rst : in std_logic;
            start : in std_logic;
            dir_in : in direction_t;
            rnd_seed : in unsigned(63 downto 0);
            done : out std_logic;
            dir_out : out direction_t
        );
    end component;

    component fission is
        port (
            clk, rst : in std_logic;
            start : in std_logic;
            particle_in : in particle_t;
            rnd_seed : in unsigned(63 downto 0);
            done : out std_logic;
            nu_produced : out integer range 0 to 4;
            base_dir_out: out direction_t;
            base_eng_out: out unsigned(15 downto 0)
        );
    end component;

    -- Componente PRNG
    component xoshiro256 is
        port (
            clk : in std_logic; rst : in std_logic;
            rnd : out unsigned(63 downto 0)
        );
    end component;

    -- =========================================================================
    -- STATE MACHINE
    -- =========================================================================
    type state_t is (
        S_IDLE,          -- Waiting for valid_in
        S_WAIT_PROB,     -- Waiting for prob_lookup to complete
        S_KERNEL_WAIT,   -- Kernel start pulse emitted, wait 1 clock for result
        S_DECIDE,        -- Kernel result ready, produce output
        S_EMITTING       -- Emitting fission daughter particles
    );
    signal state : state_t;

    -- Tipi di eventi interni
    type event_type_t is (EV_NONE, EV_SURFACE_VACUUM, EV_COLL_ABSORB, EV_COLL_SCATTER, EV_COLL_FISSION);
    signal event_decision : event_type_t;

    -- PRNG signals
    signal rnd_raw : unsigned(63 downto 0);
    signal rnd_val : unsigned(63 downto 0); -- Q16.48 in [0, 1)

    -- Probability lookup signals
    signal prob_energy_in  : unsigned(length-1 downto 0);
    signal prob_valid_in   : std_logic;
    signal prob_abs_out    : unsigned(length-1 downto 0);
    signal prob_fiss_out   : unsigned(length-1 downto 0);
    signal prob_valid_out  : std_logic;

    -- Saved context (held during prob_lookup wait)
    signal saved_particle : particle_t;
    signal saved_rnd      : unsigned(63 downto 0); -- RNG snapshot for decision

    -- Kernel interconnections
    signal abs_start  : std_logic;
    signal abs_done   : std_logic;
    signal abs_dout   : particle_t;

    signal scat_start : std_logic;
    signal scat_done  : std_logic;
    signal scat_dout  : direction_t;
    
    signal fiss_start : std_logic;
    signal fiss_done  : std_logic;
    signal fiss_nu    : integer range 0 to 4;
    signal fiss_dir   : direction_t;
    signal fiss_eng   : unsigned(15 downto 0);

    -- Fission Banking Signals  
    signal bank_counter  : integer range 0 to 4;
    signal bank_template : particle_t;
    
    -- Buffer per gestire conflitti (1 slot)
    signal conflict_valid : std_logic;
    signal conflict_p     : particle_t;
    
    constant ID_OFFSET : integer := 100;

begin

    -- =========================================================================
    -- COMPONENT INSTANCES
    -- =========================================================================
    
    -- PRNG Locale
    inst_rng : xoshiro256
        port map ( clk => clk, rst => rst, rnd => rnd_raw );

    -- Convert PRNG output to Q16.48 format [0, 1): take upper 48 bits as fractional
    rnd_val <= resize(rnd_raw(63 downto 16), 64);

    -- Probability Lookup (energy-dependent, from nuclear data tables)
    inst_prob_lookup : entity work.prob_lookup
        port map (
            clk       => clk,
            rst       => rst,
            energy_in => prob_energy_in,
            valid_in  => prob_valid_in,
            prob_abs_out  => prob_abs_out,
            prob_fiss_out => prob_fiss_out,
            valid_out     => prob_valid_out
        );
    
    -- Kernel: Absorption (1-cycle dummy)
    inst_absorption : absorption
        port map (
            clk => clk, rst => rst,
            start => abs_start,
            particle_in => saved_particle,
            done => abs_done,
            particle_out => abs_dout
        );

    -- Kernel: Scattering (~100 cycles, CORDIC pipelined)
    inst_scattering : scattering_realistic
        port map (
            clk => clk, rst => rst,
            start => scat_start,
            dir_in => saved_particle.direction,
            rnd_seed => saved_rnd,
            done => scat_done,
            dir_out => scat_dout
        );
        
    -- Kernel: Fission (1-cycle dummy)
    inst_fission : fission
        port map (
            clk => clk, rst => rst,
            start => fiss_start,
            particle_in => saved_particle,
            rnd_seed => saved_rnd,
            done => fiss_done,
            nu_produced => fiss_nu,
            base_dir_out => fiss_dir,
            base_eng_out => fiss_eng
        );

    -- =========================================================================
    -- BUSY SIGNAL: Busy when not idle OR conflict pending
    -- =========================================================================
    busy <= '0' when state = S_IDLE and conflict_valid = '0' else '1';

    -- =========================================================================
    -- MAIN STATE MACHINE
    -- =========================================================================
    process(clk, rst)
        variable v_out : particle_t;
        variable l : line;
    begin
        if rst = '1' then
            state <= S_IDLE;
            valid_out <= '0';
            particle_out <= EMPTYPARTICLE;
            
            prob_valid_in  <= '0';
            prob_energy_in <= (others => '0');
            
            abs_start  <= '0';
            scat_start <= '0';
            fiss_start <= '0';
            
            event_decision <= EV_NONE;
            saved_particle <= EMPTYPARTICLE;
            saved_rnd      <= (others => '0');
            
            bank_counter  <= 0;
            bank_template <= EMPTYPARTICLE;
            
            conflict_valid <= '0';
            conflict_p     <= EMPTYPARTICLE;
            
        elsif rising_edge(clk) then
            -- Defaults: one-clock pulses
            valid_out     <= '0';
            prob_valid_in <= '0';
            abs_start     <= '0';
            scat_start    <= '0';
            fiss_start    <= '0';
            
            case state is
                -- =============================================================
                -- S_IDLE: Waiting for new particle
                -- =============================================================
                when S_IDLE =>
                    -- Drain pending conflict first
                    if conflict_valid = '1' then
                        valid_out <= '1';
                        particle_out <= conflict_p;
                        conflict_valid <= '0';
                        
                    elsif valid_in = '1' then
                        if particle_in.nextop = OP_CROSS_SURFACE then
                            -- =============================================
                            -- SURFACE: Immediate output (no lookup needed)
                            -- =============================================
                            v_out := particle_in;
                            v_out.alive := '0';
                            v_out.nextop := OP_DYING;
                            v_out.dist_collision := (others => '0');
                            v_out.dist_boundary  := (others => '0');
                            valid_out <= '1';
                            particle_out <= v_out;
                            
                            write(l, string'("Interaction: SURFACE_LEAK, Id: "));
                            write(l, safe_id_to_int(v_out.id));
                            writeline(output, l);
                            
                        elsif particle_in.nextop = OP_COLLISION then
                            -- =============================================
                            -- COLLISION: Start prob_lookup, go wait
                            -- =============================================
                            saved_particle <= particle_in;
                            saved_rnd      <= rnd_val; -- Snapshot RNG now
                            
                            prob_energy_in <= particle_in.energy;
                            prob_valid_in  <= '1'; -- Pulse for 1 clock
                            
                            state <= S_WAIT_PROB;
                        end if;
                    end if;
                
                -- =============================================================
                -- S_WAIT_PROB: Waiting for prob_lookup to return (~77 cycles)
                -- =============================================================
                when S_WAIT_PROB =>
                    if prob_valid_out = '1' then
                        -- Probabilities available! Make collision decision.
                        if saved_rnd < prob_abs_out then
                            event_decision <= EV_COLL_ABSORB;
                            abs_start <= '1';
                        elsif saved_rnd < (prob_abs_out + prob_fiss_out) then
                            event_decision <= EV_COLL_FISSION;
                            fiss_start <= '1';
                        else
                            event_decision <= EV_COLL_SCATTER;
                            scat_start <= '1';
                        end if;
                        
                        state <= S_KERNEL_WAIT;
                    end if;
                
                -- =============================================================
                -- S_KERNEL_WAIT: Kernel start pulses were emitted last clock.
                -- Wait 1 clock for 1-cycle dummy kernels to produce results.
                -- =============================================================
                when S_KERNEL_WAIT =>
                    state <= S_DECIDE;
                
                -- =============================================================
                -- S_DECIDE: Kernel results are now valid (1 clock after start).
                -- =============================================================
                when S_DECIDE =>
                    v_out := saved_particle;
                    v_out.dist_collision := (others => '0');
                    v_out.dist_boundary  := (others => '0');
                    
                    case event_decision is
                        when EV_COLL_ABSORB =>
                            valid_out <= '1';
                            particle_out <= abs_dout;
                            state <= S_IDLE;
                            
                            write(l, string'("Interaction: ABSORPTION, Id: "));
                            write(l, safe_id_to_int(abs_dout.id));
                            writeline(output, l);
                            
                        when EV_COLL_SCATTER =>
                            v_out.direction := scat_dout;
                            v_out.alive := '1';
                            v_out.nextop := OP_ADVANCE;
                            valid_out <= '1';
                            particle_out <= v_out;
                            state <= S_IDLE;
                            
                            write(l, string'("Interaction: SCATTER, Id: "));
                            write(l, safe_id_to_int(v_out.id));
                            writeline(output, l);
                            
                        when EV_COLL_FISSION =>
                            -- FISSIONE TRIGGERED
                            write(l, string'("Interaction: FISSION, Parent Id: "));
                            write(l, safe_id_to_int(v_out.id));
                            write(l, string'(", n:"));
                            write(l, fiss_nu);
                            writeline(output, l);

                            -- TREE INDEXING ID GENERATION
                            -- Formula: Child_ID = (Parent_ID * 8) + Index
                            -- OVERFLOW PROTECTION
                            if unsigned(v_out.id(strlength-1 downto strlength-3)) /= 0 then
                                v_out.id := std_logic_vector(resize(unsigned(v_out.id(strlength-4 downto 0)) sll 3, strlength));
                            else
                                v_out.id := std_logic_vector(unsigned(v_out.id) sll 3);
                            end if;
                            
                            -- Zero-ID guard
                            if unsigned(v_out.id) = 0 then
                                v_out.id := std_logic_vector(to_unsigned(1, strlength));
                            end if;
                            
                            -- 1. Prepare Immediate Daughter (Index 1)
                            v_out.alive := '1'; 
                            v_out.direction := fiss_dir;
                            v_out.nextop := OP_ADVANCE;
                            
                            -- Save template for banking (Index 2+)
                            bank_template <= v_out; 
                            bank_template.id <= std_logic_vector(unsigned(v_out.id) + 2);
                            
                            -- Output first daughter (Index 1)
                            v_out.id := std_logic_vector(unsigned(v_out.id) + 1);
                            valid_out <= '1';
                            particle_out <= v_out;
                            
                            -- Start banking if nu > 1
                            if fiss_nu > 1 then
                                state <= S_EMITTING;
                                bank_counter <= fiss_nu - 1;
                            else
                                state <= S_IDLE;
                            end if;
                                
                        when others =>
                            state <= S_IDLE;
                    end case;
                
                -- =============================================================
                -- S_EMITTING: Emitting fission daughter particles
                -- =============================================================
                when S_EMITTING =>
                    valid_out <= '1';
                    particle_out <= bank_template;
                    
                    -- Incrementa ID per il prossimo ciclo
                    bank_template.id <= std_logic_vector(unsigned(bank_template.id) + 1);

                    write(l, string'("[TRACE] Id: "));
                    write(l, safe_id_to_int(bank_template.id));
                    write(l, string'(" Event: FISSION PRODUCT (Bank)"));
                    writeline(output, l);

                    if bank_counter > 1 then
                        bank_counter <= bank_counter - 1;
                    else
                        state <= S_IDLE;
                    end if;
                    
                    -- Handle conflict if new data arrives while busy
                    if valid_in = '1' then
                        conflict_valid <= '1';
                        v_out := particle_in;
                        v_out.alive := '0';
                        v_out.nextop := OP_DYING;
                        v_out.dist_collision := (others => '0');
                        v_out.dist_boundary  := (others => '0');
                        conflict_p <= v_out;
                    end if;
                    
            end case;
        end if;
    end process;
    
end architecture behavioral;
