library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.config.all;
use work.configopenmc.all;


entity tb_physicsworker is
end tb_physicsworker;


architecture tb of tb_physicsworker is

    component physicsworker
        port (
            clk         : in  std_logic;
            rst         : in  std_logic;

            p_in        : in  particle_t;
            p_in_valid  : in  std_logic;
            
            p_out       : out particle_t;
            p_out_valid : out std_logic
        );
    end component;

     -- Signals

    signal clk : std_logic := '0';
    signal rst : std_logic := '1';
    
    signal p_in        : particle_t := EMPTYPARTICLE;
    signal p_in_valid  : std_logic := '0';
    
    signal p_out       : particle_t;
    signal p_out_valid : std_logic;

    -- Debug Signals for GTKWave visualization
    signal debug_dist_collision : std_logic_vector(m_blocksize * m_blocks - 1 downto 0);
    
    constant CLK_PERIOD : time := 10 ns;

begin

    -- Assign debug signals
    debug_dist_collision <= std_logic_vector(p_out.dist_collision);

    uut : physicsworker
        port map (
            clk => clk,
            rst => rst,

            p_in => p_in,
            p_in_valid => p_in_valid,
            
            p_out => p_out,
            p_out_valid => p_out_valid
        );

    -- Clock Generation
    clk_process : process
    begin
        clk <= '0';
        wait for CLK_PERIOD/2;
        clk <= '1';
        wait for CLK_PERIOD/2;
    end process;

    -- Stimulus
    stim_process : process
    begin
        wait for CLK_PERIOD * 5;
        rst <= '0';
        wait until rising_edge(clk);
        
        report "Starting PhysicsWorker Throughput Test";
        
        -- STREAMING: Inject 100 particles back-to-back
        for i in 1 to 100 loop
            p_in.material <= FUEL;
            p_in.id <= std_logic_vector(to_unsigned(i, strlength)); -- ID sequenziale (strlength=64 from configopenmc)
            p_in.energy <= to_unsigned(100, 64); -- Dummy
            p_in_valid <= '1';
            wait for CLK_PERIOD;
        end loop;
        
        -- End of Stream
        p_in_valid <= '0';
        p_in.material <= VOID;
        
        -- Wait for pipeline to drain
        wait for CLK_PERIOD * 200;
        
        report "Simulation Finished";
        std.env.stop;
    end process;
    
    -- Monitor
    monitor_process : process
    begin
        wait until rst = '0';
        loop
            wait until rising_edge(clk);
            if p_out_valid = '1' then
                report "Output Valid! Dist Collision: " & to_hstring(p_out.dist_collision);
                assert p_out.dist_collision > 0 
                    report "Distance is Zero! Suspicious..." severity warning;
            end if;
        end loop;
    end process;

end tb;
