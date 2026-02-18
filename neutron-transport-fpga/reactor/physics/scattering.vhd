library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.configopenmc.all;

----------------------------------------------------------------------------------
-- Entity: scattering
-- Description: 
--   Implementa la logica di Scattering Isotropo (nel sistema del laboratorio).
--   Genera una nuova direzione casuale uniformemente distribuita sulla sfera unitaria.
--
-- Algorithm (Semplificato):
--   1. Genera coseno angolo polare mu uniform in [-1, 1].
--   2. Genera angolo azimutale phi uniform in [0, 2*PI].
--   3. Calcola le nuove componenti (richiede SIN/COS -> Cordic).
--
-- Note HW:
--   - Poiché il CORDIC è costoso, qui implementiamo una versione ultra-semplificata
--     per testare l'architettura: "Random Axis Flip + Small Perturbation".
--   - In produzione, questo modulo conterrebbe una pipeline CORDIC dedicata.
----------------------------------------------------------------------------------
entity scattering is
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;
        
        -- Input: Particella incidente e PRNG seed
        start       : in  std_logic;
        dir_in      : in  direction_t; 
        rnd_seed    : in  unsigned(63 downto 0); -- 64-bit Randomness
        
        -- Output: Nuova direzione
        done        : out std_logic;
        dir_out     : out direction_t
    );
end entity scattering;

architecture rtl of scattering is

begin
    -- istanzio sincos module
    
    -- IMPLEMENTAZIONE MOCK (HIGH THROUGHPUT):
    -- Invece di vera trigonometria, facciamo una permutazione e inversione casuale degli assi.
    -- Questo "rompe" la traiettoria rettilinea ed è sufficiente per validare il loop del reattore.
    
    process(clk, rst)
        -- Interpretiamo i bit del seme casuale come comandi
        variable cmd_swap : std_logic;
        variable cmd_sign_x : std_logic;
        variable cmd_sign_y : std_logic;
        variable cmd_sign_z : std_logic;
        variable v_out : direction_t;
    begin
        if rst = '1' then
            done <= '0';
            dir_out.vx <= (others => '0');
            dir_out.vy <= (others => '0');
            dir_out.vz <= (others => '0');
        elsif rising_edge(clk) then
            done <= start; -- 1 ciclo di latenza
            
            if start = '1' then
                    -- Estrai comandi dai bit bassi del random
                    cmd_swap   := rnd_seed(0);
                    cmd_sign_x := rnd_seed(1);
                    cmd_sign_y := rnd_seed(2);
                    cmd_sign_z := rnd_seed(3);
                    
                    v_out := dir_in;
                    
                    -- 1. Swap Assi (Mescola X e Y)
                    if cmd_swap = '1' then
                        v_out.vx := dir_in.vy;
                        v_out.vy := dir_in.vx;
                    end if;
                    
                    -- 2. Inversione Segni (Scattering in avanti o indietro)
                    if cmd_sign_x = '1' then v_out.vx := -v_out.vx; end if;
                    if cmd_sign_y = '1' then v_out.vy := -v_out.vy; end if;
                    if cmd_sign_z = '1' then v_out.vz := -v_out.vz; end if;
                    
                    -- 3. Evitiamo vettore nullo (se input era nullo o tutti cancellati)
                    -- Forziamo un valore minimo se tutto zero (caso patologico iniziale)
                    if v_out.vx = 0 and v_out.vy = 0 and v_out.vz = 0 then
                        v_out.vx := x"0000000000000001"; -- Small epsilon
                    end if;
                    
                    dir_out <= v_out;

            end if;
        end if;
    end process;

end architecture rtl;
