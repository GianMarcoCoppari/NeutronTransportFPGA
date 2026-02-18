library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.configopenmc.all;

----------------------------------------------------------------------------------
-- Entity: TransportFSM
-- Description: 
--   High-level Transport State Machine (Kernel).
--   Manages the lifecycle of a Monte Carlo particle:
--     1. Initialization (OP_INIT)
--     2. Advance Loop (OP_ADVANCE) - check collision vs boundary
--     3. Collision Handling (OP_COLLISION)
--     4. Surface Crossing (OP_CROSS_SURFACE)
--     5. Termination/Tallying (OP_TALLY -> OP_DYING)
--
-- Logic:
--   Acts as a router functionality. In a full pipeline implementation, this
--   logic might be distributed across the pipeline stages. Here, it simulates
--   the sequential decision making of the transport loop.
----------------------------------------------------------------------------------
entity TransportFSM is 
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;

        validin     : in  std_logic;      -- Valid processed particle from previous stage/queue
        particlein  : in  particle_t;     -- Current particle state
        
        validout    : out std_logic;      -- Output valid signal
        particleout : out particle_t      -- Updated particle state
    );
end entity TransportFSM;


architecture behavioral of TransportFSM is
begin 

    computestage : process (clk, rst) 
        variable nextparticle : particle_t := EMPTYPARTICLE;

    begin 
        if rst = '1' then 
            validout    <= '0';
            particleout <= EMPTYPARTICLE;

        else 
            if rising_edge(clk) then 
                -- logica di trasporto
                -- ogni stato ricopia la sequenza C++
                
                -- 1) Synchroonus Default Assignment
                validout <= validin;
                particleout <= particlein;

                -- 2) Se valido, aggiorna lo stato
                if validin = '1' then 
                    validout <= '1'; -- aggiornato al possimo colpo di clock, insieme a particleout
                    nextparticle := particlein; -- aggiornata subito, così i dati originali non vanno persi

                    if nextparticle.alive = '0' and nextparticle.nextop /= OP_DYING then 
                        nextparticle.nextop := OP_TALLY;
                    else
                        -- qui la particella è viva o sta andando a morire
                        -- copio il flusso di codice C++, ogni funzione
                        -- è eseguita da uno stato della FSM
                        case nextparticle.nextop is
                            when OP_INIT      => 
                                -- Semplificazione: niente XS_LOOKUP esplicito.
                                -- I worker faranno fetch XS dentro Advance.
                                nextparticle.nextop := OP_ADVANCE;

                            -- OP_XS_LOOKUP rimosso per ottimizzazione pipeline

                            when OP_ADVANCE  => 
                                -- Il worker Advance ha calcolato e mosso.
                                -- Il Router decide solo il branch.
                                -- Geometria Box Vacuum: attraversamento = Morte.
                                if nextparticle.dist_collision > nextparticle.dist_boundary then
                                    -- Collisione oltre il bordo -> Leakage (Morte)
                                    nextparticle.nextop := OP_TALLY; 
                                    -- Nota: in scenari complessi sarebbe CROSS_SURFACE
                                else
                                    -- Collisione entro la cella -> Urto
                                    nextparticle.nextop := OP_COLLISION;
                                end if;

                            when OP_CROSS_SURFACE =>
                                -- Stato deprecato per geometria Box singola.
                                -- Mantenuto per compatibilità o rimosso logicamente.
                                nextparticle.nextop := OP_TALLY;

                            when OP_COLLISION => 
                                -- Dopo collisione (scattering), si riparte.
                                -- Il controllo "alive" è fatto dal worker collisione.
                                if nextparticle.alive = '1' then
                                    nextparticle.nextop := OP_ADVANCE;
                                else
                                    nextparticle.nextop := OP_TALLY;
                                end if;

                            when OP_TALLY     => 
                                nextparticle.nextop := OP_DYING;

                            when OP_DYING     => 
                                nextparticle.nextop := OP_DYING;

                            when others       => 
                                nextparticle.nextop := OP_DYING;
                        end case; -- next operation
                    end if; -- check alive

                    particleout <= nextparticle;
                end if; -- check validin
            end if; -- rising edge
        end if; -- rst
    end process computestage;
end architecture behavioral;