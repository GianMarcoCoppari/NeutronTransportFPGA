-- filepath: /home/gianmarco/openmc/utils/vhdl/test/tb_transportpl.vhd
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use work.configopenmc.all;

entity tb_transportpl is
end entity tb_transportpl;

architecture behavioral of tb_transportpl is

    -- Componente sotto test (Device Under Test)
    component transportpl is
        port (
            clk          : in  std_logic;
            rst          : in  std_logic;
            start        : in  std_logic;
            ready        : out std_logic;
            particle_in  : in  particle_t;
            done         : out std_logic;
            particle_out : out particle_t
        );
    end component;

    -- Segnali
    signal clk        : std_logic := '0';
    signal rst        : std_logic := '0';
    signal start      : std_logic := '0';
    signal ready      : std_logic;
    signal done       : std_logic;
    
    signal p_in       : particle_t := EMPTYPARTICLE;
    signal p_out      : particle_t;

    -- Contatori per verifica
    signal sent_count : integer := 0;
    signal recv_count : integer := 0;

    constant CLK_PERIOD : time := 10 ns;
    
    -- Numero di particelle da iniettare nel burst
    constant BURST_SIZE : integer := 50; 

    -- Helper per debug segnali complessi in GTKWave
    signal debug_dist_coll : std_logic_vector(63 downto 0);
    signal debug_dist_bound: std_logic_vector(63 downto 0);
    signal debug_next_op   : operation_t;

begin

    -- Istanza DUT
    uut : transportpl
        port map (
            clk          => clk,
            rst          => rst,
            start        => start,
            ready        => ready,
            particle_in  => p_in,
            done         => done,
            particle_out => p_out
        );

    -- Collegamento segnali di debug
    debug_dist_coll  <= std_logic_vector(p_out.dist_collision);
    debug_dist_bound <= std_logic_vector(p_out.dist_boundary);
    debug_next_op    <= p_out.nextop;

    -- Generazione Clock
    clk_process : process
    begin
        clk <= '0'; wait for CLK_PERIOD/2;
        clk <= '1'; wait for CLK_PERIOD/2;
    end process;

    -- ==========================================================
    -- PROCESSO 1: INJECTOR (Genera dati ad alta velocità)
    -- ==========================================================
    stimulus : process
    begin
        -- Reset Iniziale
        rst <= '1';
        start <= '0';
        wait for CLK_PERIOD * 5;
        rst <= '0';
        wait for CLK_PERIOD * 2;

        report "--- INIZIO BURST STREAMING ---";

        for i in 1 to BURST_SIZE loop
            -- Setup dati particella
            start <= '1';
            
            -- Creiamo particelle leggermente diverse (usa ID come contatore)
            p_in.id <= std_logic_vector(to_unsigned(i, 16));
            p_in.material <= FUEL; 
            p_in.energy   <= to_unsigned(100, 64); -- 100 eV
            
            -- Posizione fissa o variabile (opzionale)
            p_in.position.x <= (others => '0'); -- Origine
            p_in.position.y <= (others => '0');
            p_in.position.z <= (others => '0');
            
            -- Direzione fissa (+X)
            -- TRUCCO SCALING: Usiamo '1' (raw integer) invece di '1.0' (fixed point)
            -- perché il divisore hardware n/d non ha pre-shift, quindi d deve essere unitario.
            -- Con vx=1, Distanza = (Bound / 1) = Bound (correttamente scalato).
            p_in.direction.vx <= x"0000000000000001"; 
            p_in.direction.vy <= (others => '0');
            p_in.direction.vz <= (others => '0');

            sent_count <= i;

            -- Invia al fronte di salita
            wait for CLK_PERIOD; 
        end loop;

        -- Fine iniezione
        start <= '0';
        p_in <= EMPTYPARTICLE; -- Pulisci bus input
        
        report "--- BURST COMPLETATO (Inviate: " & integer'image(BURST_SIZE) & ") ---";
        report "--- Attesa svuotamento pipeline... ---";

        -- Attendiamo abbastanza tempo per far uscire tutto (Latenza ~130 cicli)
        wait for 3000 ns; 
        
        -- Verifica Finale
        if recv_count = BURST_SIZE then
            report "TEST SUPERATO: Ricevute tutte le particelle (" & integer'image(recv_count) & ")";
        else
            report "TEST FALLITO: Perse delle particelle! (Inv: " & integer'image(BURST_SIZE) & ", Ric: " & integer'image(recv_count) & ")" severity error;
        end if;

        std.env.stop;
        wait;
    end process stimulus;

    -- ==========================================================
    -- PROCESSO 2: COLLECTOR (Verifica output asincrono)
    -- ==========================================================
    check : process(clk)
        variable l : line;
    begin
        if rising_edge(clk) then
            if done = '1' then
                recv_count <= recv_count + 1;
                
                -- Stampa info per ogni particella uscita
                write(l, string'("OUT [Time: "));
                write(l, now);
                write(l, string'("] ID:"));
                write(l, to_integer(unsigned(p_out.id)));
                write(l, string'(" Op:"));
                
                if p_out.nextop = OP_COLLISION then
                    write(l, string'(" COLLISION "));
                elsif p_out.nextop = OP_CROSS_SURFACE then
                    write(l, string'(" SURFACE_X "));
                else
                    write(l, string'(" UNKNOWN   "));
                end if;

                write(l, string'(" BoundDist:"));
                hwrite(l, std_logic_vector(p_out.dist_boundary));
                
                write(l, string'(" CollDist:"));
                hwrite(l, std_logic_vector(p_out.dist_collision));

                writeline(output, l);
            end if;
        end if;
    end process check;

end architecture behavioral;