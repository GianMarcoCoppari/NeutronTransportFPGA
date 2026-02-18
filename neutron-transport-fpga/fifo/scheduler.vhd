library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.configopenmc.all;

----------------------------------------------------------------------------------
-- Entity: scheduler
-- Description: 
--   Modulo Top-Level che gestisce il ciclo di vita delle particelle.
--   Integra:
--     1. FIFO (Coda di lavoro)
--     2. Pipeline (Transport Physics + Geometry)
--     3. Logica di Feedback (Router)
--
-- Funzionamento:
--   - Accetta nuove particelle dall'esterno (Host) e le mette in FIFO.
--   - Quando la pipeline è libera, preleva dalla FIFO e lancia.
--   - All'uscita della pipeline:
--       - Se ALIVE e dentro i bordi: Rimette in FIFO (Feedback).
--       - Se DEAD o ESCAPE: Manda all'uscita "Finished".
----------------------------------------------------------------------------------
entity scheduler is
    port (
        clk : in std_logic;
        rst : in std_logic;
        
        -- External Injection Interface (Input)
        inject_valid      : in std_logic;
        inject_particle   : in particle_t;
        scheduler_ready   : out std_logic; -- '1' se c'è spazio per iniettare
        
        -- Finished Output Interface (Output)
        -- Particelle completate (assorbite o uscite)
        finished_valid    : out std_logic;
        finished_particle : out particle_t;
        
        -- Simulator Status
        busy              : out std_logic  -- '1' se ci sono particelle nel sistema (FIFO o Pipeline)
    );
end entity scheduler;

architecture rtl of scheduler is

    -- Componenti
    component particle_fifo is
        generic ( DEPTH_LOG2 : integer );
        port (
            clk, rst : in std_logic;
            din : in particle_t; wr_en : in std_logic; full : out std_logic;
            dout : out particle_t; rd_en : in std_logic; empty : out std_logic;
            data_count : out integer
        );
    end component;

    component transportpl is
        port (
            clk, rst : in std_logic;
            start : in std_logic;
            ready : out std_logic;
            particle_in : in particle_t;
            done : out std_logic;
            particle_out : out particle_t
        );
    end component;

    component eventworker is
        port (
            clk         : in  std_logic;
            rst         : in  std_logic;
            valid_in    : in  std_logic;
            particle_in : in  particle_t;
            valid_out   : out std_logic;
            particle_out: out particle_t;
            busy        : out std_logic
        );
    end component;

    -- Segnali FIFO
    signal fifo_din       : particle_t;
    signal fifo_wr_en     : std_logic;
    signal fifo_full      : std_logic;
    signal fifo_dout      : particle_t;
    signal fifo_rd_en     : std_logic;
    signal fifo_empty     : std_logic;
    signal fifo_count     : integer; -- Generico intero

    -- Segnali Pipeline
    signal pipe_start     : std_logic;
    signal pipe_ready     : std_logic;
    signal pipe_p_in      : particle_t;
    signal pipe_done      : std_logic;
    signal pipe_p_out     : particle_t;

    -- Segnali Event Worker
    signal ev_done        : std_logic;
    signal ev_p_out       : particle_t;
    signal ev_busy        : std_logic;

    -- Segnali Feedback
    signal feedback_req   : std_logic; -- Richiesta di feedback dalla pipeline

    -- Segnali Material Lookup (Automatic Material Management)
    signal lookup_cell_id : std_logic_vector(ncells-1 downto 0);
    signal lookup_mat     : material_t;

    -- Stato per gestire la lettura dalla FIFO (wait state per latency ram sincrona)
    type state_t is (IDLE, WAIT_MEM, FETCH);
    signal state : state_t := IDLE;

    -- Counters for Simulation Status
    signal total_particles : integer := 0;
    signal pending_box     : integer := 0; -- Tracks pipeline balance (Starts - Ends)

    -- Constants
    constant FIFO_DEPTH : integer := 256; -- Should match 2**DEPTH_LOG2
    constant RESERVED_FEEDBACK : integer := 32; -- Safety margin for recirculation

begin

    -- =========================================================================
    -- 0. MATERIAL LOOKUP INSTANCE
    -- Ensures that any particle entering the FIFO has the correct material
    -- corresponding to its Cell ID.
    -- =========================================================================
    -- Priority Mux matching the Process Logic below (Feedback > Injection)
    lookup_cell_id <= ev_p_out.cellid when ev_done = '1' else inject_particle.cellid;

    inst_mat_lookup : entity work.materiallookup
        port map (
            clk      => clk,
            cell_id  => lookup_cell_id,
            material => lookup_mat
        );

    -- =========================================================================
    -- 1. ISTANZA FIFO (Work Queue)
    -- =========================================================================
    inst_fifo : particle_fifo
        generic map ( DEPTH_LOG2 => 8 ) -- 2^8 = 256
        port map (
            clk   => clk,
            rst   => rst,
            
            -- Write Port (Multiplexed: Host vs Feedback)
            din   => fifo_din,
            wr_en => fifo_wr_en,
            full  => fifo_full,
            
            -- Read Port (Verso Pipeline)
            dout  => fifo_dout,
            rd_en => fifo_rd_en,
            empty => fifo_empty,
            
            data_count => fifo_count
        );

    -- =========================================================================
    -- 2. ARBITRO DI INGRESSO (Feedback Priority)
    -- Logica: Chi scrive nella FIFO? 
    -- Priorità assoluta al Feedback per evitare deadlock (se la pipeline sputa fuori
    -- roba e la FIFO è piena, si blocca tutto se non diamo priorità a chi esce
    -- rispetto a chi vuole entrare da fuori).
    --
    -- Tuttavia, se la FIFO è PIENA, il feedback si blocca comunque.
    -- Soluzione Reale: Usare soglie "Almost Full" per fermare l'iniezione esterna
    -- prima che sia veramente piena, lasciando spazio per il feedback in volo.
    -- =========================================================================
    
    process(inject_valid, inject_particle, ev_done, ev_p_out, fifo_full, lookup_mat) begin
        -- Default
        fifo_wr_en <= '0';
        fifo_din   <= EMPTYPARTICLE;
        scheduler_ready <= '0';
        
        -- Logic Output
        finished_valid <= '0';
        finished_particle <= EMPTYPARTICLE;

        -- Gestione Output Pipeline -> EventWorker -> Router
        if ev_done = '1' then
            -- Se la particella è viva e non è uscita -> Feedback
            if ev_p_out.alive = '1' and ev_p_out.nextop /= OP_DYING then
                 -- Feedback to FIFO
                 fifo_din   <= ev_p_out;
                 -- AUTO-CORRECT MATERIAL
                 fifo_din.material <= lookup_mat; 
                 
                 fifo_wr_en <= '1';
                 
                 -- Se la FIFO è piena qui, perdiamo la particella! 
                 -- (In design robusti serve backpressure sulla pipeline, ma transportpl non ha hold)
            else
                 -- Particella terminata -> Output
                 finished_valid <= '1';
                 finished_particle <= ev_p_out;
                 -- Note: No need to correct material for output, it's dead/finished
            end if;
        
        -- Se la pipeline non sta scrivendo, accettiamo dall'esterno (Host)
        elsif inject_valid = '1' then
            -- Accettiamo SOLO se c'è spazio sufficiente (Almost Full Logic)
            -- Lasciamo RESERVED_FEEDBACK slot liberi per le particelle interne.
            if fifo_count < (FIFO_DEPTH - RESERVED_FEEDBACK) then
                fifo_din   <= inject_particle;
                -- AUTO-CORRECT MATERIAL
                fifo_din.material <= lookup_mat;
                
                fifo_wr_en <= '1';
                scheduler_ready <= '1'; -- Ack
            else
                scheduler_ready <= '0'; -- Backpressure to Host
            end if;
        else
            -- Idle: segnaliamo ready basandoci sulla stessa logica Almost Full
            if fifo_count < (FIFO_DEPTH - RESERVED_FEEDBACK) then
                scheduler_ready <= '1';
            else
                scheduler_ready <= '0';
            end if;
        end if;
    end process;


    -- =========================================================================
    -- 3. DISPATCHER (FIFO -> Pipeline)
    -- Preleva dalla FIFO e lancia nella pipeline.
    -- La FIFO sincrona ha 1 ciclo di latenza di lettura.
    -- State Machine per gestire il fetch.
    -- =========================================================================
    process(clk, rst) begin
        if rst = '1' then
            state <= IDLE;
            fifo_rd_en <= '0';
            pipe_start <= '0';
            pipe_p_in  <= EMPTYPARTICLE;
        else 
            if rising_edge(clk) then
                -- Defaults
                fifo_rd_en <= '0';
                pipe_start <= '0';

                case state is
                    when IDLE =>
                        -- Se c'è qualcosa da fare e la pipeline è pronta 
                        -- (e l'EventWorker non è occupato a emettere figli)
                        if fifo_empty = '0' and pipe_ready = '1' and ev_busy = '0' then
                            fifo_rd_en <= '1'; -- Richiedi lettura
                            state <= WAIT_MEM;
                        end if;

                    when WAIT_MEM =>
                        -- Attesa latenza RAM FIFO (1 ciclo di clock)
                        -- Al rising edge attuale, la FIFO campiona rd_en.
                        -- Al prossimo rising edge, dout sarà stabile.
                        state <= FETCH;
                    
                    when FETCH =>
                        -- Ora fifo_dout è valido
                        pipe_p_in  <= fifo_dout;
                        pipe_start <= '1';
                        
                        state <= IDLE;
                        
                end case; -- state
            end if; -- rising edge
        end if; -- rst
    end process;

    -- =========================================================================
    -- 4. ISTANZA PIPELINE
    -- =========================================================================
    inst_pipeline : transportpl
        port map (
            clk          => clk,
            rst          => rst,
            start        => pipe_start,
            ready        => pipe_ready,
            particle_in  => pipe_p_in,
            done         => pipe_done,
            particle_out => pipe_p_out
        );

    -- =========================================================================
    -- 5. ISTANZA EVENT WORKER (Physics & Decision)
    -- =========================================================================
    inst_eventworker : eventworker
        port map (
            clk          => clk,
            rst          => rst,
            valid_in     => pipe_done,
            particle_in  => pipe_p_out,
            valid_out    => ev_done,
            particle_out => ev_p_out,
            busy         => ev_busy
        );
        
    -- =========================================================================
    -- STATO GLOBALE (Particle Counting & Busy Logic)
    -- =========================================================================
    process(clk)
        variable delta : integer;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                total_particles <= 0;
                pending_box <= 0;
            else
                delta := 0;
                
                -- 1. Injection (Source)
                if inject_valid = '1' then 
                    delta := delta + 1; 
                end if;
                
                -- 2. Removal (Sink)
                if finished_valid = '1' then 
                    delta := delta - 1; 
                end if;
                
                -- 3. Generation (Fission Secondaries)
                -- If we receive an output (ev_done) but the "debt" of the pipeline (pending_box)
                -- is already paid (<= 0), then this is a NEW extra particle (Generation).
                -- Note: ev_done signals a particle leaving the black box.
                if ev_done = '1' and pending_box <= 0 then
                    delta := delta + 1;
                end if;
                
                total_particles <= total_particles + delta;
                
                -- Update Pending Box Counter (Pipeline/Box Occupancy Balance)
                -- Increments on entry (pipe_start), decrements on exit (ev_done).
                if pipe_start = '1' and ev_done = '0' then
                    pending_box <= pending_box + 1;
                elsif pipe_start = '0' and ev_done = '1' then
                    pending_box <= pending_box - 1;
                end if;
                -- If both happen, pending_box stays stable.
            end if;
        end if;
    end process;

    -- Busy is true if there are ANY particles tracked in the system.
    busy <= '1' when total_particles > 0 else '0';

end architecture rtl;
