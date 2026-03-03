library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use ieee.std_logic_textio.all;
use work.config.all;
use work.configopenmc.all;

--------------------------------------------------------------------------------
-- Testbench: tb_id_immediate
-- Purpose: Verificare che gli ID siano visibili IMMEDIATAMENTE dopo iniezione
--          nei primi 100 cicli, prima che la pipeline li processi.
--------------------------------------------------------------------------------
entity tb_id_immediate is
end entity tb_id_immediate;

architecture testbench of tb_id_immediate is

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

    constant CLK_PERIOD : time := 10 ns;
    signal clk : std_logic := '0';
    signal rst : std_logic := '1';
    signal stop_sim : boolean := false;

    signal inject_valid      : std_logic := '0';
    signal inject_particle   : particle_t := EMPTYPARTICLE;
    signal scheduler_ready   : std_logic;
    signal finished_valid    : std_logic;
    signal finished_particle : particle_t;
    signal busy              : std_logic;

    signal cycle_count : integer := 0;

begin

    clk <= not clk after CLK_PERIOD/2 when not stop_sim;

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

    -- Contatore cicli
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '0' then
                cycle_count <= cycle_count + 1;
            end if;
        end if;
    end process;

    -- Monitor IMMEDIATO: mostra ID nel ciclo esatto di iniezione
    immediate_monitor : process(clk)
        variable l : line;
    begin
        if rising_edge(clk) then
            if inject_valid = '1' and scheduler_ready = '1' then
                write(l, string'("Ciclo "));
                write(l, cycle_count);
                write(l, string'(": Inject ID=0x"));
                hwrite(l, inject_particle.id);
                write(l, string'(" ("));
                write(l, to_integer(unsigned(inject_particle.id(15 downto 0))));
                write(l, string'(" dec)"));
                writeline(output, l);
            end if;
        end if;
    end process;

    -- Stimulus: Inietta 100 particelle rapidamente
    stimulus : process
        variable l : line;
    begin
        wait for 100 ns;
        rst <= '0';
        wait for CLK_PERIOD;

        write(l, string'("=============================================="));
        writeline(output, l);
        write(l, string'("INIEZIONE 100 PARTICELLE - MONITOR IMMEDIATO"));
        writeline(output, l);
        write(l, string'("Aspettativa: ID in hex = 8, 10, 18, 20, 28..."));
        writeline(output, l);
        write(l, string'("            (in dec: 8, 16, 24, 32, 40...)"));
        writeline(output, l);
        write(l, string'("=============================================="));
        writeline(output, l);

        -- Inietta 100 particelle il più rapidamente possibile
        for i in 1 to 100 loop
            -- Aspetta ready
            wait until rising_edge(clk);
            while scheduler_ready = '0' loop
                wait until rising_edge(clk);
            end loop;
            
            -- Prepara particella con ID = i*8
            inject_particle.id <= std_logic_vector(to_unsigned(i * 8, strlength));
            inject_particle.alive <= '1';
            inject_particle.cellid <= std_logic_vector(to_unsigned(1, 10));
            inject_particle.material <= FUEL;
            inject_particle.direction.vx <= x"0001000000000000";
            inject_particle.energy <= x"000000023810960F";
            inject_particle.position.x <= (others => '0');
            inject_particle.position.y <= (others => '0');
            inject_particle.position.z <= (others => '0');
            inject_particle.nextop <= OP_ADVANCE;
            inject_valid <= '1';
            
            wait until rising_edge(clk);
            inject_valid <= '0';
        end loop;

        write(l, string'("=============================================="));
        writeline(output, l);
        write(l, string'("Fine iniezione. Ciclo corrente: "));
        write(l, cycle_count);
        writeline(output, l);
        write(l, string'("=============================================="));
        writeline(output, l);

        -- Aspetta processamento
        wait until busy = '0' for 200 us;
        wait for CLK_PERIOD * 10;

        write(l, string'("TEST COMPLETATO"));
        writeline(output, l);
        
        stop_sim <= true;
        wait;
    end process;

end architecture testbench;
