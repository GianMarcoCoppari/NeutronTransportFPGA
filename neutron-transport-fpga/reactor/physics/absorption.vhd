library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.configopenmc.all;

----------------------------------------------------------------------------------
-- Entity: absorption
-- Description: 
--   Gestisce l'evento di CATTURA (Absorption).
--   La particella cessa di esistere (alive = 0).
--   In simulazioni reali, qui si registrerebbe il deposito di energia (Tally/Score).
----------------------------------------------------------------------------------
entity absorption is
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;
        
        start       : in  std_logic;
        particle_in : in  particle_t;
        
        -- Output
        done        : out std_logic;
        particle_out: out particle_t
    );
end entity absorption;

architecture rtl of absorption is

begin

    process(clk, rst) begin
        if rst = '1' then
            done <= '0';
            particle_out <= EMPTYPARTICLE;
        elsif rising_edge(clk) then
            done <= start; -- 1 ciclo di latenza (dummy)
            
            if start = '1' then
                particle_out <= particle_in;
                
                -- LOGICA DI MORTE
                particle_out.alive  <= '0';
                particle_out.nextop <= OP_DYING; 
                
                -- Opzionale: Azzera peso o energia per pulizia
                -- particle_out.weight <= (others => '0');
            end if;
        end if;
    end process;

end architecture rtl;
