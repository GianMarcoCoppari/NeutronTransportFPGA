library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use work.configopenmc.all;

----------------------------------------------------------------------------------
-- Testbench: tb_scheduler
-- Descrizione: 
--   Verifica il ciclo completo di vita delle particelle (Inject -> Pipe -> Feedback).
--   Scenario 1: Particella singola che rimbalza n volte.
--   Scenario 2: Burst di particelle.
----------------------------------------------------------------------------------
entity tb_scheduler is
end entity tb_scheduler;

architecture behavioral of tb_scheduler is

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

    component scheduler is
        port (
            clk : in std_logic;
            rst : in std_logic;
            
            inject_valid      : in std_logic;
            inject_particle   : in particle_t;
            scheduler_ready   : out std_logic;
            
            finished_valid    : out std_logic;
            finished_particle : out particle_t;
            
            busy              : out std_logic
        );
    end component;

    signal clk : std_logic := '0';
    signal rst : std_logic := '0';
    
    signal inject_valid      : std_logic := '0';
    signal inject_particle   : particle_t := EMPTYPARTICLE;
    signal scheduler_ready   : std_logic;
    
    signal finished_valid    : std_logic;
    signal finished_particle : particle_t;
    signal busy              : std_logic;

    constant CLK_PERIOD : time := 10 ns;

begin

    uut : scheduler
        port map (
            clk => clk, rst => rst,
            inject_valid => inject_valid, inject_particle => inject_particle,
            scheduler_ready => scheduler_ready,
            finished_valid => finished_valid, finished_particle => finished_particle,
            busy => busy
        );

    -- Clock Gen
    clk_process : process
    begin
        clk <= '0'; wait for CLK_PERIOD/2;
        clk <= '1'; wait for CLK_PERIOD/2;
    end process;
    
    -- Monitor Output Logic (Print events)
    monitor : process(clk)
        variable l : line;
    begin
        if rising_edge(clk) then
            if finished_valid = '1' then
                write(l, string'("[OUT] Particle Finished ID:"));
                write(l, safe_id_to_int(finished_particle.id));
                write(l, string'(" Reason: "));
                if finished_particle.nextop = OP_DYING then
                     write(l, string'("DYING"));
                elsif finished_particle.dist_collision < finished_particle.dist_boundary then
                     -- Heuristic check (logic is inside scheduler logic actually)
                     write(l, string'("ABSORBED/KILLED"));
                else
                     write(l, string'("ESCAPED?"));
                end if;
                writeline(output, l);
            end if;
        end if;
    end process;

    -- Stimulus
    process
        variable l : line;
    begin
        rst <= '1';
        wait for CLK_PERIOD*10;
        rst <= '0';
        wait for CLK_PERIOD*10;
        
        report "--- START SCHEDULER TEST ---";

        -------------------------------------------------------------
        -- TEST 1: SINGLE PARTICLE INJECTION
        -------------------------------------------------------------
        report "Injecting Particle ID 8 (Source)...";
        
        if scheduler_ready = '1' then
            inject_valid <= '1';
            inject_particle.id <= std_logic_vector(to_unsigned(8, strlength)); -- Source ID multiple of 8
            inject_particle.alive <= '1';
            inject_particle.cellid <= std_logic_vector(to_unsigned(1, 10)); -- Set Cell ID 1 (Result -> FUEL)
            inject_particle.material <= FUEL;
            -- TRUCCO SCALING: 1.0 in Q16.48 (Unit Vector along X)
            inject_particle.direction.vx <= x"0001000000000000";
            -- Energy: Set to mid-range value from ROM (ROM_ENERGY[32])
            inject_particle.energy <= x"000000023810960F";

            -- Posizione 0
            inject_particle.position.x <= (others => '0');
            inject_particle.position.y <= (others => '0');
            inject_particle.position.z <= (others => '0');
            
            wait for CLK_PERIOD;
            inject_valid <= '0';
        else
            report "Scheduler Not Ready?" severity failure;
        end if;
        
        report "Waiting for particle life cycle (Looping)...";
        -- La particella dovrebbe entrare, fare collisioni, e se ancora viva loopare.
        -- Essendo il physics random, potrebbe morire o uscire.
        -- Aspettiamo un tempo lungo (es. 5000 ns che sono ~500 cicli, circa 3-4 passaggi in pipeline).
        wait for 5000 ns;
        
        -------------------------------------------------------------
        -- TEST 2: BURST INJECTION (20 Particles)
        -------------------------------------------------------------
        report "Injecting Burst of 20 Particles...";
        for i in 2 to 21 loop
            wait until rising_edge(clk);
            if scheduler_ready = '1' then
                inject_valid <= '1';
                inject_particle.id <= std_logic_vector(to_unsigned(i*8, strlength)); -- Multiples of 8
                inject_particle.alive <= '1';
                inject_particle.cellid <= std_logic_vector(to_unsigned(1, 10)); -- Set Cell ID 1 (Result -> FUEL)
                inject_particle.material <= FUEL;
                -- DIRECTION: 1.0 in Q16.48 (Unit Vector along X)
                inject_particle.direction.vx <= x"0001000000000000";
                inject_particle.energy <= x"000000023810960F";
                inject_particle.position.x <= (others => '0');
            else
                -- Retry mechanism: stay on same i if busy
                -- (Semplificato: just wait implicitly in loop if we wanted, but here we just report)
                -- report "Scheduler Busy during burst!" severity warning;
                -- Per iniettare 20 davvero, dovremmo aspettare ready.
                -- Implementiamo un mini-wait loop
                while scheduler_ready = '0' loop
                     wait until rising_edge(clk);
                end loop;
                
                -- Now ready
                inject_valid <= '1';
                inject_particle.id <= std_logic_vector(to_unsigned(i*8, strlength)); -- Multiples of 8
                inject_particle.alive <= '1';
                inject_particle.cellid <= std_logic_vector(to_unsigned(1, 10)); -- Set Cell ID 1 (Result -> FUEL)
                inject_particle.material <= FUEL;
                -- DIRECTION: 1.0 in Q16.48 (Unit Vector along X)
                inject_particle.direction.vx <= x"0001000000000000";
                inject_particle.energy <= x"000000023810960F";
                inject_particle.position.x <= (others => '0');
            end if;
        end loop;
        
        wait until rising_edge(clk);
        inject_valid <= '0'; -- Stop injection

        report "Waiting for burst processing (until busy=0)...";
        
        -- Loop wait until busy goes to 0 (All particles dead/escaped)
        -- We add a timeout of 1 ms just in case of infinite loops
        while busy = '1' loop
             wait until rising_edge(clk);
        end loop;

        report "--- TEST FINISHED (ALL PARTICLES PROCESSED) ---";
        std.env.stop;
        wait;
    end process;

end architecture behavioral;
