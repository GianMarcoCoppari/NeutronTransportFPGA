-- filepath: /home/gianmarco/openmc/utils/vhdl/reactor/transport.vhd
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.configopenmc.all;

----------------------------------------------------------------------------------
-- Entity: transportpl
-- Description: 
--   High-Performance Streaming Transport Kernel.
--   It saturates the math pipelines by injecting one particle per clock cycle
--   when 'start' is asserted.
----------------------------------------------------------------------------------
entity transportpl is
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;
        
        -- Control Interface
        start        : in  std_logic;      -- '1' = Inject valid particles (Streaming Mode)
        ready        : out std_logic;      -- '1' always, unless backpressure logic is added
        
        -- Data Interface
        particle_in  : in  particle_t;     -- Valid input particle (sampled when start='1')
        
        done         : out std_logic;      -- '1' when a valid result exits the pipeline
        particle_out : out particle_t      -- Resulting particle
    );
end entity transportpl;

architecture behavioral of transportpl is 
    -- Interconnect Signals
    signal phys_valid_out  : std_logic;
    signal phys_param_out  : particle_t;
    signal geom_busy       : std_logic;

begin

    -- Ready is effectively always '1' in this feed-forward pipeline
    -- (Assuming downstream can always accept result, or we drop it)
    ready <= '1'; 

    -- ===========================================================================
    -- 1. PHYSICS STAGE
    -- ===========================================================================
    instphysics : entity work.physicsworker
        port map (
            clk         => clk,
            rst         => rst,
            
            -- Direct Connection: Inject when 'start' is high
            p_in_valid  => start,         
            p_in        => particle_in,
            
            p_out_valid => phys_valid_out, 
            p_out       => phys_param_out
        );

    -- ===========================================================================
    -- 2. GEOMETRY STAGE (Chained)
    -- ===========================================================================
    instgeometry : entity work.geometryworker
        port map (
            clk         => clk,
            rst         => rst,
            busy        => geom_busy,
            -- Chain valid signal from Physics
            validin     => phys_valid_out,  
            particlein  => phys_param_out,
            
            -- Final Output
            validout    => done,          -- Pulse 'done' whenever a particle exits
            particleout => particle_out
        );

end architecture behavioral;