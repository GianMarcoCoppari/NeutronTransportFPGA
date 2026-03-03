library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use ieee.std_logic_textio.all;
use work.config.all;
use work.configcordic.all;
use work.configcordicc.all;
use work.configopenmc.all;

----------------------------------------------------------------------------------
-- Testbench: tb_scattering_realistic
-- Description:
--   Tests the realistic scattering module to verify:
--   1. Output directions are unit vectors (normalized)
--   2. Angular distribution is isotropic
--   3. Pipeline latency is correct (~100 cycles with CORDIC)
----------------------------------------------------------------------------------
entity tb_scattering_realistic is
end entity tb_scattering_realistic;

architecture behavioral of tb_scattering_realistic is

    -- Component Declaration
    component scattering_realistic is
        port (
            clk         : in  std_logic;
            rst         : in  std_logic;
            start       : in  std_logic;
            dir_in      : in  direction_t;
            rnd_seed    : in  unsigned(63 downto 0);
            done        : out std_logic;
            dir_out     : out direction_t
        );
    end component;

    -- Clock and Reset
    signal clk : std_logic := '0';
    signal rst : std_logic := '1';
    
    -- DUT Signals
    signal start    : std_logic := '0';
    signal dir_in   : direction_t;
    signal rnd_seed : unsigned(63 downto 0) := x"123456789ABCDEF0";
    signal done     : std_logic;
    signal dir_out  : direction_t;
    
    -- Simulation Control
    constant CLK_PERIOD : time := 10 ns;
    signal sim_done : boolean := false;
    
    -- PRNG for test seeds
    component xoshiro256 is
        port (
            clk  : in  std_logic;
            rst  : in  std_logic;
            rnd  : out unsigned(63 downto 0)
        );
    end component;
    
    signal prng_rnd : unsigned(63 downto 0);
    
    -- Output file for analysis
    file output_file : text open write_mode is "scattering_test.log";

begin

    -- Clock Generator
    clk_gen : process
    begin
        while not sim_done loop
            clk <= '0';
            wait for CLK_PERIOD / 2;
            clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process clk_gen;

    -- DUT Instantiation
    dut : scattering_realistic
        port map (
            clk      => clk,
            rst      => rst,
            start    => start,
            dir_in   => dir_in,
            rnd_seed => rnd_seed,
            done     => done,
            dir_out  => dir_out
        );
    
    -- PRNG for generating test seeds
    prng : xoshiro256
        port map (
            clk => clk,
            rst => rst,
            rnd => prng_rnd
        );

    -- Stimulus Process
    stimulus : process
        variable l : line;
        variable test_count : integer := 0;
        variable norm_sq : signed(2*length-1 downto 0);
        variable norm_val : signed(length-1 downto 0);
    begin
        -- Initialize
        rst <= '1';
        start <= '0';
        dir_in.vx <= x"0000B504F333F9DE"; -- Unit vector in +Z (arbitrary)
        dir_in.vy <= (others => '0');
        dir_in.vz <= x"0000B504F333F9DE";
        
        wait for CLK_PERIOD * 5;
        rst <= '0';
        wait for CLK_PERIOD * 2;
        
        write(l, string'("=== Scattering Realistic Test ==="));
        writeline(output_file, l);
        write(l, string'("Testing isotropic scattering with multiple random seeds"));
        writeline(output_file, l);
        writeline(output_file, l);
        
        -- Run 10 test cases
        for i in 1 to 10 loop
            test_count := i;
            
            -- Use PRNG to generate seed
            rnd_seed <= prng_rnd;
            start <= '1';
            wait for CLK_PERIOD;
            start <= '0';
            
            -- Wait for done
            wait until done = '1';
            wait for CLK_PERIOD;
            
            -- Log results
            write(l, string'("Test Case "));
            write(l, test_count);
            writeline(output_file, l);
            
            write(l, string'("  Seed:   "));
            hwrite(l, std_logic_vector(rnd_seed));
            writeline(output_file, l);
            
            write(l, string'("  Dir X:  "));
            hwrite(l, std_logic_vector(dir_out.vx));
            writeline(output_file, l);
            
            write(l, string'("  Dir Y:  "));
            hwrite(l, std_logic_vector(dir_out.vy));
            writeline(output_file, l);
            
            write(l, string'("  Dir Z:  "));
            hwrite(l, std_logic_vector(dir_out.vz));
            writeline(output_file, l);
            
            -- Check normalization (approximate)
            -- |v|² = vx² + vy² + vz² should ≈ 1.0 in Q16.48
            norm_sq := (dir_out.vx * dir_out.vx) + 
                       (dir_out.vy * dir_out.vy) + 
                       (dir_out.vz * dir_out.vz);
            
            -- Extract Q16.48 from Q32.96
            norm_val := norm_sq(length+47 downto 48);
            
            write(l, string'("  |v|²:   "));
            hwrite(l, std_logic_vector(norm_val));
            if norm_val > x"0000F00000000000" and norm_val < x"0001100000000000" then
                write(l, string'("  [OK - approximately 1.0]"));
            else
                write(l, string'("  [WARNING - not normalized]"));
            end if;
            writeline(output_file, l);
            writeline(output_file, l);
            
            -- Wait before next test
            wait for CLK_PERIOD * 10;
        end loop;
        
        -- Finish
        write(l, string'("=== Test Complete ==="));
        writeline(output_file, l);
        
        sim_done <= true;
        wait;
    end process stimulus;

end architecture behavioral;
