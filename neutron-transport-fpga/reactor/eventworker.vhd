library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all; -- Added for debug
use ieee.std_logic_textio.all; -- Added for debug
use work.configopenmc.all;

----------------------------------------------------------------------------------
-- Entity: eventworker
-- Description: 
--   Gestisce l'evento post-trasporto.
--   Accetta particelle che hanno completato uno step di geometria (COLLISION o SURFACE).
--
-- Logic Flow:
--   1. SURFACE CROSSING:
--      - Controlla tipo di superficie (Vacuum vs Reflective).
--      - Se Vacuum -> Kill (Finished).
--      - Se Reflective -> Inverti componente velocità (Bounce).
--
--   2. COLLISION:
--      - Usa PRNG per decidere tipo reazione (Absorption vs Scattering).
--      - Se Absorption -> Kill.
--      - Se Scattering -> Chiama ScatteringKernel (nuova direzione).
----------------------------------------------------------------------------------
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

    -- Tipi di eventi interni
    type event_type_t is (EV_NONE, EV_SURFACE_VACUUM, EV_COLL_ABSORB, EV_COLL_SCATTER, EV_COLL_FISSION);
    
    signal event_decision : event_type_t;
    signal event_reg      : event_type_t;

    -- Segnali PRNG
    signal rnd_val      : unsigned(63 downto 0);
    constant THRESHOLD_ABS     : unsigned(63 downto 0) := x"1999999999999999"; -- 10%
    constant THRESHOLD_FISSION : unsigned(63 downto 0) := x"3333333333333333"; -- 20% (Accumulato, solo esempio)

    -- Pipeline Signals
    signal pipe_valid_in_d : std_logic;
    signal pipe_particle_d : particle_t;

    -- Interconnessioni Kernels
    signal abs_start : std_logic;
    signal abs_done  : std_logic;
    signal abs_dout  : particle_t;

    signal scat_start : std_logic;
    signal scat_done  : std_logic;
    signal scat_dout  : direction_t;
    
    signal fiss_start : std_logic;
    signal fiss_done  : std_logic;
    signal fiss_nu    : integer range 0 to 4;
    signal fiss_dir   : direction_t;
    signal fiss_eng   : unsigned(15 downto 0);

    -- Banking State Machine Signals
    type bank_state_t is (S_IDLE, S_EMITTING);
    signal bank_state    : bank_state_t := S_IDLE;
    signal bank_counter  : integer range 0 to 4;
    signal bank_template : particle_t;
    
    -- Buffer per gestire conflitti (1 slot)
    signal conflict_valid : std_logic;
    signal conflict_p     : particle_t;
    signal conflict_reg   : event_type_t;
    
    constant ID_OFFSET : integer := 100;

begin

    -- Istanza PRNG Locale
    inst_rng : xoshiro256
        port map ( clk => clk, rst => rst, rnd => rnd_val );

    ----------------------------------------------------------------------------
    -- STADIO 1: DECISIONE LOGICA (Combinatoriale)
    ----------------------------------------------------------------------------
    process(valid_in, particle_in, rnd_val)
    begin
        event_decision <= EV_NONE;
        abs_start <= '0';
        scat_start <= '0';
        fiss_start <= '0';

        if valid_in = '1' then
            -- Default reset distanze logicamente qui (ma applicato dopo)
            
            if particle_in.nextop = OP_CROSS_SURFACE then
                -- SURFACE (Vacuum)
                event_decision <= EV_SURFACE_VACUUM;
                
            elsif particle_in.nextop = OP_COLLISION then
                -- COLLISION
                -- Logica Semplificata: Abs vs Fission vs Scatter
                -- Usiamo soglie cumulative
                if rnd_val < THRESHOLD_ABS then
                    event_decision <= EV_COLL_ABSORB;
                    abs_start <= '1';
                elsif rnd_val < (THRESHOLD_ABS + THRESHOLD_FISSION) then
                    -- FISSIONE (nuova!)
                    event_decision <= EV_COLL_FISSION;
                    fiss_start <= '1';
                else
                    event_decision <= EV_COLL_SCATTER;
                    scat_start <= '1';
                end if;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------------
    -- STADIO 2: ISTANZA KERNELS & PIPELINE REGISTERS
    ----------------------------------------------------------------------------
    
    inst_absorption : absorption
        port map (
            clk => clk, rst => rst,
            start => abs_start,
            particle_in => particle_in,
            done => abs_done,
            particle_out => abs_dout
        );

    inst_scattering : scattering_realistic
        port map (
            clk => clk, rst => rst,
            start => scat_start,
            dir_in => particle_in.direction,
            rnd_seed => rnd_val, -- Usa lo stesso seed usato per la decisione (o successivo, va bene uguale per random)
            done => scat_done,
            dir_out => scat_dout
        );
        
    inst_fission : fission
        port map (
            clk => clk, rst => rst,
            start => fiss_start,
            particle_in => particle_in,
            rnd_seed => rnd_val,
            done => fiss_done,
            nu_produced => fiss_nu,
            base_dir_out => fiss_dir,
            base_eng_out => fiss_eng
        );

    -- Delay Line per mantenere il contesto della particella durante l'elaborazione dei kernel
    process(clk, rst)
        variable v_p : particle_t;
    begin
        if rst = '1' then
            pipe_valid_in_d <= '0';
            pipe_particle_d <= EMPTYPARTICLE;
            event_reg <= EV_NONE;
        elsif rising_edge(clk) then
            pipe_valid_in_d <= valid_in;
            event_reg <= event_decision;
            
            -- Copia particella e resetta distanze (preparazione per output)
            if valid_in = '1' then
                v_p := particle_in;
                v_p.dist_collision := (others => '0');
                v_p.dist_boundary  := (others => '0');
                pipe_particle_d <= v_p;
            end if;
        end if; 
    end process;

    ----------------------------------------------------------------------------
    -- STADIO 3: OUTPUT MUX & BANKING
    ----------------------------------------------------------------------------
    -- Gestione complessa: Fissione può produrre N particelle.
    
    busy <= '1' when bank_state = S_EMITTING or conflict_valid = '1' else '0';

    process(clk, rst)
        variable v_out : particle_t;
        variable l : line; -- Debug line
    begin
        if rst = '1' then
            valid_out <= '0';
            particle_out <= EMPTYPARTICLE;
            
            bank_state    <= S_IDLE;
            bank_counter  <= 0;
            bank_template <= EMPTYPARTICLE;
            
            conflict_valid <= '0';
            conflict_p     <= EMPTYPARTICLE;
            conflict_reg   <= EV_NONE;
            
        elsif rising_edge(clk) then
            valid_out <= '0';
            
            case bank_state is
                when S_IDLE =>
                    -- Se avevamo un conflitto pendente, processiamolo ora
                    if conflict_valid = '1' then
                         -- TODO: Refactoring per evitare duplicazione codice logic output
                         -- Per brevità: Non gestiamo conflitti FISSION su conflitti. 
                         -- Assumiamo che il conflitto sia roba semplice (Scattering/Abs).
                         -- Se c'è un'altra Fissione nel conflitto, perdiamo i secondari > 1 per ora.
                         valid_out <= '1';
                         particle_out <= conflict_p; -- Già processata prima di stash
                         conflict_valid <= '0';
                         
                    elsif pipe_valid_in_d = '1' then
                        v_out := pipe_particle_d;
        
                        case event_reg is
                            when EV_SURFACE_VACUUM =>
                                v_out.alive := '0';
                                v_out.nextop := OP_DYING;
                                valid_out <= '1';
                                particle_out <= v_out;
                                
                                write(l, string'("Interaction: SURFACE_LEAK, Id: "));
                                write(l, safe_id_to_int(v_out.id));
                                writeline(output, l);
                                
                            when EV_COLL_ABSORB =>
                                valid_out <= '1';
                                particle_out <= abs_dout;
                                
                                write(l, string'("Interaction: ABSORPTION, Id: "));
                                write(l, safe_id_to_int(abs_dout.id));
                                writeline(output, l);
                                
                            when EV_COLL_SCATTER =>
                                v_out.direction := scat_dout;
                                v_out.alive := '1';
                                v_out.nextop := OP_ADVANCE;
                                valid_out <= '1';
                                particle_out <= v_out;
                                
                                write(l, string'("Interaction: SCATTER, Id: "));
                                write(l, safe_id_to_int(v_out.id));
                                writeline(output, l);
                                
                            when EV_COLL_FISSION =>
                                -- FISSIONE TRIGGERED

                                -- 1. Trace Parent Event (BEFORE ID CHANGE)
                                write(l, string'("Interaction: FISSION, Parent Id: "));
                                write(l, safe_id_to_int(v_out.id));
                                write(l, string'(", n:"));
                                write(l, fiss_nu);
                                writeline(output, l);

                                -- 2. TREE INDEXING ID GENERATION
                                -- Formula: Child_ID = (Parent_ID * 8) + Index
                                -- Using 3 bits (x8) prevents collision with Source IDs (multiples of 8)
                                -- capable of handling up to 7 children (Index 1..7) without overflow to next multiple.
                                -- Current Max Nu = 4.
                                
                                -- OVERFLOW PROTECTION: Check if upper bits are non-zero before shift
                                -- If ID is too large (upper 3 bits occupied), wrap using modulo to prevent zero IDs
                                if unsigned(v_out.id(strlength-1 downto strlength-3)) /= 0 then
                                    -- Risk of overflow detected - use modulo to keep ID in safe range
                                    -- Keep lower bits to maintain uniqueness within generation
                                    write(l, string'("WARNING: ID overflow risk detected, applying modulo"));
                                    writeline(output, l);
                                    v_out.id := std_logic_vector(resize(unsigned(v_out.id(strlength-4 downto 0)) sll 3, strlength));
                                else
                                    -- Safe to shift without overflow
                                    v_out.id := std_logic_vector(unsigned(v_out.id) sll 3);
                                end if;
                                
                                -- DEBUG: Verify shifted ID is not zero
                                write(l, string'("DEBUG: After shift, base ID = "));
                                write(l, safe_id_to_int(v_out.id));
                                writeline(output, l);
                                
                                -- CRITICAL CHECK: If ID became zero, it indicates overflow bug
                                if unsigned(v_out.id) = 0 then
                                    write(l, string'("ERROR: FISSION generated ZERO ID - parent was too large!"));
                                    writeline(output, l);
                                    -- Force non-zero ID to prevent silent failures
                                    v_out.id := std_logic_vector(to_unsigned(1, strlength));
                                end if;
                                
                                -- 3. Prepare Immediate Daughter (Index 1)
                                v_out.alive := '1'; 
                                v_out.direction := fiss_dir;
                                v_out.nextop := OP_ADVANCE;
                                
                                -- Save Base ID for Bank (Base = Parent*8)
                                bank_template <= v_out; 
                                -- Set Bank Template ID to first BANK child (Index 2)
                                bank_template.id <= std_logic_vector(unsigned(v_out.id) + 2);
                                
                                -- Set Immediate Output ID to Index 1
                                v_out.id := std_logic_vector(unsigned(v_out.id) + 1);

                                write(l, string'("  -> Child Created (Immediate), Id: "));
                                write(l, safe_id_to_int(v_out.id));
                                writeline(output, l);

                                valid_out <= '1';
                                particle_out <= v_out;
                                
                                -- Se nu > 1, attiva Banking
                                if fiss_nu > 1 then
                                    bank_state <= S_EMITTING;
                                    bank_counter <= fiss_nu - 1;
                                    -- bank_template is set above
                                end if;
                                
                            when others =>
                                valid_out <= '0';
                        end case;
                    end if;
                    
                when S_EMITTING =>
                    -- Emetti particele dal Bank
                    valid_out <= '1';
                    particle_out <= bank_template; -- Emetti copia (ID corrente: Base+2, Base+3...)
                    
                    -- Incrementa ID per il prossimo ciclo (se ce ne sono altri)
                    bank_template.id <= std_logic_vector(unsigned(bank_template.id) + 1);

                    write(l, string'("[TRACE] Id: "));
                    write(l, safe_id_to_int(bank_template.id));
                    write(l, string'(" Event: FISSION PRODUCT (Bank)"));
                    writeline(output, l);

                    if bank_counter > 1 then
                        bank_counter <= bank_counter - 1;
                    else
                        bank_state <= S_IDLE;
                    end if;
                    
                    -- Se arriva un nuovo dato mentre siamo busy emitting?
                    if pipe_valid_in_d = '1' then
                         conflict_valid <= '1';
                         -- Pre-elabora e salva
                         if event_reg = EV_COLL_SCATTER then
                             v_out := pipe_particle_d;
                             v_out.direction := scat_dout;
                             v_out.alive := '1';
                             v_out.nextop := OP_ADVANCE;
                             conflict_p <= v_out;
                         elsif event_reg = EV_COLL_ABSORB then
                             conflict_p <= abs_dout;
                         else
                             -- Surface o Fission su Fission (Edge case!)
                             -- Se fissione su fissione mentre busy, perdiamo i secondari del conflitto
                             v_out := pipe_particle_d;
                             v_out.alive := '0'; 
                             v_out.nextop := OP_DYING;
                             conflict_p <= v_out;
                         end if;
                    end if;
                    
            end case;
        end if;
    end process;
    
end architecture behavioral;
