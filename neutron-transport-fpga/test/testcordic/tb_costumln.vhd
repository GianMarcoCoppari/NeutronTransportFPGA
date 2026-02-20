-- filepath: /home/gianmarco/openmc/utils/vhdl/test/testcordic/tb_customln.vhd
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use std.textio.all;
use work.configopenmc.all;
use work.configcordic.all; -- Per m_maxiter

entity tb_customln is
end entity tb_customln;

architecture behavioral of tb_customln is

    component customln is
        port (
            clk   : in  std_logic;
            rst   : in  std_logic;
            win   : in  signed(63 downto 0);
            lnout : out signed(63 downto 0)
        );
    end component;

    signal clk : std_logic := '0';
    signal rst : std_logic := '0';
    signal win      : signed(63 downto 0) := (others => '0');
    signal lnout    : signed(63 downto 0);
    
    constant CLK_PERIOD : time := 10 ns;
    
    -- Calcolo Latenza Totale attesa: 
    -- 1 ciclo Prep Input (customln) + m_maxiter Stadi (cordich) + 0 ciclo Output (comb)
    -- In totale m_maxiter + 1 cicli di pipeline depth.
    constant LATENCY : integer := m_maxiter + 1; 

    -- Test Vectors
    type test_vec_t is array (integer range <>) of real;
    constant TEST_INPUTS : test_vec_t(0 to 19) := (
        -- Small values (approaching 0)
        0.00005, 0.0001, 0.001, 0.005, 0.01,
        -- Range < 1
        0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.99,
        -- Range > 1
        1.01, 1.10, 1.50, 2.0, 10.0, 100.0, 1000.0, 10000.0
    );

    function to_fixed(val : real) return signed is
        variable r : real;
        variable s : signed(63 downto 0) := (others => '0');
        variable is_neg : boolean := false;
    begin
        r := val * (2.0**48);
        if r < 0.0 then
            is_neg := true;
            r := -r;
        end if;
        
        for i in 62 downto 0 loop
            if r >= (2.0**i) then
                s(i) := '1';
                r := r - (2.0**i);
            end if;
        end loop;
        
        if is_neg then
            return -s;
        else
            return s;
        end if;
    end function;
    
    function to_real(val : signed) return real is
        variable r : real := 0.0;
    begin
        for i in 0 to 62 loop
            if val(i) = '1' then
                r := r + (2.0**i);
            end if;
        end loop;
        
        if val(63) = '1' then
            r := r - (2.0**63);
        end if;
        
        return r / (2.0**48);
    end function;

begin

    uut : customln
        port map (
            clk   => clk,
            rst   => rst,
            win   => win,
            lnout => lnout
        );

    -- Clock Gen
    clk <= not clk after CLK_PERIOD/2;

    -- Stimulus & Response Checker (Single Process for synchronous ease)
    process
        variable v_input : real;
        variable v_expected : real;
        variable v_actual : real;
        variable v_err : real;
        variable i_check : integer := 0;
        variable l : line;
        variable cycle_cnt : integer := 0;
    begin
        rst <= '1';
        wait for CLK_PERIOD * 5;
        rst <= '0';
        wait until rising_edge(clk); -- Sync

        report "--- START PIPELINED STRESS TEST ---";
        report "Pipeline Latency estimated at: " & integer'image(LATENCY) & " cycles";

        -- Fase 1: INIEZIONE DATI (1 per ciclo)
        for i in TEST_INPUTS'range loop
            -- Setup Input i
            win <= to_fixed(TEST_INPUTS(i));
            
            -- Se siamo già oltre la latenza, controlliamo l'output del dato (i - LATENCY)
            -- Ma per semplicità, separiamo iniezione e controllo con due loop o un array di delay
            -- Qui uso un approccio ibrido: Faccio viaggiare tutti, poi aspetto.
            
            -- NOTA: In un vero testbench complesso si userebbe una coda/FIFO per verificare 
            -- output valid in parallelo, ma qui lanciamo 10 valori e poi aspettiamo.

            wait for CLK_PERIOD; -- Next cycle
        end loop;
        
        -- Stop input (mettiamo 0 o 1, ininfluente per i dati già entrati)
        win <= to_fixed(1.0); 

        -- Fase 2: ATTESA E CONTROLLO
        -- I dati usciranno tra [LATENCY] cicli dal loro inserimento.
        -- Noi ne abbiamo inseriti 10 in 10 cicli.
        -- Il primo (i=0) esce al ciclo LATENCY (relativo allo start dell'i=0).
        -- Noi siamo ora al ciclo 10 (relativo allo start).
        -- Dobbiamo aspettare ancora (LATENCY - 10) cicli per vedere il primo.
        
        wait for CLK_PERIOD * (LATENCY - TEST_INPUTS'length + 1);

        -- Fase 3: LETTURA OUTPUT STREAMING
        report "--- CHECKING OUTPUTS ---";
        for i in TEST_INPUTS'range loop
            -- Campiona output
            v_actual := to_real(lnout);
            v_input  := TEST_INPUTS(i);
            v_expected := log(v_input);
            v_err := abs(v_actual - v_expected);

            write(l, string'("Sample ")); write(l, i);
            write(l, string'(" | In: ")); write(l, v_input);
            write(l, string'(" | Out: ")); write(l, v_actual);
            write(l, string'(" | Exp: ")); write(l, v_expected);
            write(l, string'(" | Err: ")); write(l, v_err);
            writeline(output, l);

            -- Check tolleranza (Fixed Point ha precisione limitata, specialmente per log piccoli)
            -- Errore accettabile ~ 1e-4 o 1e-5
            assert v_err < 0.001 
                report "Error too high!" severity warning;

            wait for CLK_PERIOD; -- Avanza per leggere il prossimo dato della pipeline
        end loop;

        report "--- TEST COMPLETE ---";
        std.env.stop;
        wait;
    end process;

end architecture behavioral;