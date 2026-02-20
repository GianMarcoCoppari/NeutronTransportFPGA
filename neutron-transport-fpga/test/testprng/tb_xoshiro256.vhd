-- filepath: /home/gianmarco/openmc/utils/vhdl/test/tb_xoshiro256.vhd
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all; -- Per stampare output a console

entity tb_xoshiro256 is
end entity tb_xoshiro256;

architecture behavioral of tb_xoshiro256 is

    -- Component declaration
    component xoshiro256 is
        port (
            clk  : in  std_logic;
            rst  : in  std_logic;
            rnd  : out unsigned(63 downto 0)
        );
    end component;

    -- Segnali di test
    signal clk_tb : std_logic := '0';
    signal rst_tb : std_logic := '0';
    signal rnd_tb : unsigned(63 downto 0);

    -- Costante periodo clock
    constant CLK_PERIOD : time := 10 ns;

begin

    -- Istanza Unit Under Test (UUT)
    uut : xoshiro256
        port map (
            clk => clk_tb,
            rst => rst_tb,
            rnd => rnd_tb
        );

    -- Generazione Clock
    clk_process : process
    begin
        clk_tb <= '0';
        wait for CLK_PERIOD / 2;
        clk_tb <= '1';
        wait for CLK_PERIOD / 2;
    end process;

    -- Processo di Stimolo e Monitoraggio
    stim_proc : process
        variable l : line; -- Variabile per output su console
    begin
        -- 1. Reset iniziale
        rst_tb <= '1';
        wait for CLK_PERIOD * 2;
        rst_tb <= '0';
        
        report "============================================";
        report "Inizio simulazione Xoshiro256**";
        report "============================================";

        -- 2. Attendiamo qualche ciclo per riempire la pipeline
        wait for CLK_PERIOD * 2;

        -- 3. Loop di acquisizione dati (10 campioni)
        for i in 1 to 10 loop
            wait until rising_edge(clk_tb);
            wait for 1 ns; -- Delta delay per leggere output stabile

            -- Stampa a video del valore esadecimale
            write(l, string'("Cycle "));
            write(l, i);
            write(l, string'(": RND = 0x"));
            hwrite(l, std_logic_vector(rnd_tb));
            writeline(output, l);

            -- Controllo base: Assicuriamoci che non sia zero (evento raro ma possibile, qui indica reset o errore)
            -- Nota: lo zero è un output valido per xoshiro**, ma statisticamente improbabile in 10 colpi.
            -- Per test rigorosi si usano suite come Dieharder su file di output.
            assert rnd_tb /= 0 
                report "Attenzione: Output Zero rilevato (potrebbe essere corretto o errore di reset/init)" 
                severity note;
        end loop;

        report "============================================";
        report "Test concluso. Controllare output sopra.";
        report "============================================";
        
        -- Terminazione simulazione
        std.env.stop;
        wait;
    end process;

end architecture behavioral;