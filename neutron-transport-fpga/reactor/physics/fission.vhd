library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.configopenmc.all;

----------------------------------------------------------------------------------
-- Entity: fission
-- Description: 
--   Gestisce l'evento di FISSIONE.
--   Il neutrone incidente viene ASSORBITO (muore).
--   Vengono generati N neutroni secondari (prompt neutrons).
--
-- Logic:
--   1. Determina 'nu' (molteplicità):
--      - Fisicamente per U235 termico è circa 2.43.
--      - Qui useremo una probabilità semplice: 57% -> 2, 43% -> 3.
--   2. Determina le proprietà dei secondari:
--      - Energia: Campionata da spettro di Watt (qui: Mock/Fisso).
--      - Direzione: Isotropa (qui: Mock/Random Flip).
----------------------------------------------------------------------------------
entity fission is
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;
        
        -- Input
        start       : in  std_logic;
        particle_in : in  particle_t;
        rnd_seed    : in  unsigned(63 downto 0); -- Randomness
        
        -- Output
        done        : out std_logic;
        
        -- Risultati Fissione
        nu_produced : out integer range 0 to 4; -- Numero di neutroni generati
        
        -- Proprietà base per i figli (per ora uguali per tutti, 
        -- ma in futuro l'EventWorker potrebbe iterare e perturbare)
        base_dir_out: out direction_t;
        base_eng_out: out unsigned(15 downto 0) -- Placeholder width
    );
end entity fission;

architecture rtl of fission is
    
    -- Soglia per decidere se nu=2 o nu=3
    -- 0.57 * 2^64 (approssimato) -> nu media ~ 2.43
    constant THRESHOLD_NU : unsigned(63 downto 0) := x"91EB851EB851EB85"; 

begin

    process(clk, rst)
        variable v_rnd : unsigned(63 downto 0);
    begin
        if rst = '1' then
            done <= '0';
            nu_produced <= 0;
            base_dir_out.vx <= (others => '0');
            base_dir_out.vy <= (others => '0');
            base_dir_out.vz <= (others => '0');
        elsif rising_edge(clk) then
            done <= start; -- 1 ciclo latenza
            
            if start = '1' then
                v_rnd := rnd_seed;
                
                -- 1. Calcolo Nu (Molteplicità)
                if v_rnd < THRESHOLD_NU then
                    nu_produced <= 2;
                else
                    nu_produced <= 3;
                end if;
                
                -- 2. Direzione (Mock: Inverti incidente per ora, o random semplice)
                -- L'EventWorker userà questa come base e applicherà variazioni per ogni figlio
                -- per evitare che 3 neutroni partano sovrapposti.
                base_dir_out.vx <= -particle_in.direction.vx;
                base_dir_out.vy <= -particle_in.direction.vy; 
                base_dir_out.vz <= -particle_in.direction.vz;
                
                -- 3. Energia (Mock: Spettro di fissione medio ~ 2 MeV)
                -- Qui non abbiamo unità, mettiamo un valore dummy
                -- base_eng_out <= ...
                
            end if;
        end if;
    end process;

end architecture rtl;
