library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use ieee.std_logic_textio.all;
use work.config.all;
use work.configopenmc.all;

--------------------------------------------------------------------------------
-- Testbench: tb_id_propagation
-- Purpose: Verificare che l'ID delle particelle viene propagato correttamente
--          attraverso tutta la pipeline senza diventare zero.
--------------------------------------------------------------------------------
entity tb_id_propagation is
end entity tb_id_propagation;

architecture testbench of tb_id_propagation is

    -- Helper function
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

    -- Clock & Reset
    constant CLK_PERIOD : time := 10 ns;
    signal clk : std_logic := '0';
    signal rst : std_logic := '1';
    signal stop_sim : boolean := false;

    -- DUT Signals
    signal inject_valid      : std_logic := '0';
    signal inject_particle   : particle_t := EMPTYPARTICLE;
    signal scheduler_ready   : std_logic;
    signal finished_valid    : std_logic;
    signal finished_particle : particle_t;
    signal busy              : std_logic;

    -- Test Tracking
    signal test_phase : integer := 0;
    signal injected_count : integer := 0;
    signal finished_count : integer := 0;

begin

    -- Clock Generator
    clk <= not clk after CLK_PERIOD/2 when not stop_sim;

    -- DUT Instance
    dut : scheduler
        port map (
            clk => clk,
            rst => rst,
            inject_valid      => inject_valid,
            inject_particle   => inject_particle,
            scheduler_ready   => scheduler_ready,
            finished_valid    => finished_valid,
            finished_particle => finished_particle,
            busy              => busy
        );

    -- Monitor Process: Controlla TUTTI gli ID in output
    monitor_proc : process(clk)
        variable l : line;
    begin
        if rising_edge(clk) then
            if finished_valid = '1' then
                finished_count <= finished_count + 1;
                
                write(l, string'("[FINISHED] Particle #"));
                write(l, finished_count + 1);
                write(l, string'(" ID = 0x"));
                hwrite(l, finished_particle.id);
                write(l, string'(" (dec "));
                write(l, safe_id_to_int(finished_particle.id));
                write(l, string'(")"));
                
                -- CHECK CRITICO: L'ID è zero?
                if unsigned(finished_particle.id) = 0 then
                    write(l, string'(" *** ERROR: ZERO ID DETECTED! ***"));
                end if;
                
                writeline(output, l);
            end if;
        end if;
    end process;

    -- Stimulus Process
    stimulus : process
        variable l : line;
        variable expected_id : integer;
    begin
        wait for 100 ns;
        rst <= '0';
        wait for CLK_PERIOD * 2;

        report "========================================";
        report "TEST: ID Propagation Check";
        report "Injecting 20 particles with IDs: 8, 16, 24, 32...";
        report "========================================";

        test_phase <= 1;

        -- Inietta 20 particelle con ID multipli di 8
        for i in 1 to 20 loop
            expected_id := i * 8;
            
            wait until rising_edge(clk);
            
            -- Aspetta che scheduler sia ready
            while scheduler_ready = '0' loop
                wait until rising_edge(clk);
            end loop;
            
            -- Prepara particella
            inject_particle.id <= std_logic_vector(to_unsigned(expected_id, strlength));
            inject_particle.alive <= '1';
            inject_particle.cellid <= std_logic_vector(to_unsigned(1, 10));
            inject_particle.material <= FUEL;
            inject_particle.direction.vx <= x"0001000000000000"; -- Unit vector X
            inject_particle.energy <= x"000000023810960F";
            inject_particle.position.x <= (others => '0');
            inject_particle.position.y <= (others => '0');
            inject_particle.position.z <= (others => '0');
            inject_particle.nextop <= OP_ADVANCE;
            
            inject_valid <= '1';
            
            write(l, string'("[INJECT] Particle #"));
            write(l, i);
            write(l, string'(" ID = 0x"));
            hwrite(l, std_logic_vector(to_unsigned(expected_id, strlength)));
            write(l, string'(" (dec "));
            write(l, expected_id);
            write(l, string'(")"));
            writeline(output, l);
            
            injected_count <= injected_count + 1;
            
            wait until rising_edge(clk);
            inject_valid <= '0';
        end loop;

        report "All particles injected. Waiting for processing...";
        test_phase <= 2;

        -- Aspetta che tutte le particelle vengano processate
        wait until busy = '0' for 100 us;
        
        if busy = '1' then
            report "WARNING: Timeout waiting for busy='0'" severity warning;
        end if;

        wait for CLK_PERIOD * 10;

        report "========================================";
        report "TEST COMPLETED";
        write(l, string'("Injected: "));
        write(l, injected_count);
        write(l, string'(" | Finished: "));
        write(l, finished_count);
        writeline(output, l);
        report "========================================";

        stop_sim <= true;
        wait;
    end process;

end architecture testbench;
