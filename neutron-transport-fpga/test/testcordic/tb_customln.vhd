library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use ieee.std_logic_textio.all;
use work.config.all;
use work.configcordic.all;
use work.configcordich.all;

----------------------------------------------------------------------------------
-- Testbench: tb_customln
-- Verifies numerical correctness of customln module.
-- customln computes -ln(win) using hyperbolic CORDIC vectoring.
--
-- Test values (Q16.48 format, 1.0 = 0x0001_0000_0000_0000):
--   win = 0.5  -> -ln(0.5) = 0.6931...  -> expected ~ 0x0000_B172_17F7_D1CF
--   win = 0.25 -> -ln(0.25) = 1.3862... -> expected ~ 0x0001_62E4_2FEF_A39E
--   win = 0.1  -> -ln(0.1) = 2.3025...  -> expected ~ 0x0002_4D76_3776_AAA2
--   win = 0.75 -> -ln(0.75) = 0.2876... -> expected ~ 0x0000_49A7_84BC_D1B8
--   win = 0.9  -> -ln(0.9) = 0.1053...  -> expected ~ 0x0000_1AF1_6B11_C6D1
----------------------------------------------------------------------------------
entity tb_customln is
end entity tb_customln;

architecture behavioral of tb_customln is

    signal clk   : std_logic := '0';
    signal rst   : std_logic := '1';
    signal win   : signed(63 downto 0) := (others => '0');
    signal lnout : signed(63 downto 0);

    constant CLK_PERIOD : time := 10 ns;
    
    -- Pipeline latency: m_maxiterh + a few extra cycles
    constant PIPE_LATENCY : integer := m_maxiterh + 5;

    -- Q16.48 constants
    constant ONE_Q16 : signed(63 downto 0) := x"0001_0000_0000_0000"; -- 1.0

    -- Test input values in Q16.48
    constant VAL_0_5  : signed(63 downto 0) := x"0000_8000_0000_0000"; -- 0.5
    constant VAL_0_25 : signed(63 downto 0) := x"0000_4000_0000_0000"; -- 0.25
    constant VAL_0_1  : signed(63 downto 0) := x"0000_1999_9999_999A"; -- 0.1
    constant VAL_0_75 : signed(63 downto 0) := x"0000_C000_0000_0000"; -- 0.75
    constant VAL_0_9  : signed(63 downto 0) := x"0000_E666_6666_6666"; -- 0.9

    -- Expected -ln(x) values in Q16.48 (for reference, allow ~1% tolerance)
    constant EXP_LN_0_5  : signed(63 downto 0) := x"0000_B172_17F7_D1CF"; -- 0.6931
    constant EXP_LN_0_25 : signed(63 downto 0) := x"0001_62E4_2FEF_A39E"; -- 1.3862
    constant EXP_LN_0_1  : signed(63 downto 0) := x"0002_4D76_3776_AAA2"; -- 2.3025
    constant EXP_LN_0_75 : signed(63 downto 0) := x"0000_49A7_84BC_D1B8"; -- 0.2876
    constant EXP_LN_0_9  : signed(63 downto 0) := x"0000_1AF1_6B11_C6D1"; -- 0.1053

begin

    -- Clock generation
    clk <= not clk after CLK_PERIOD / 2;

    -- DUT
    dut : entity work.customln(rtl)
        port map (
            clk   => clk,
            rst   => rst,
            win   => win,
            lnout => lnout
        );

    -- Stimulus process
    stim : process
        variable l : line;
        
        procedure wait_cycles(n : integer) is
        begin
            for i in 1 to n loop
                wait until rising_edge(clk);
            end loop;
        end procedure;
        
        procedure test_value(
            input_val : signed(63 downto 0);
            expected  : signed(63 downto 0);
            label_str : string
        ) is
            variable v_result : signed(63 downto 0);
            variable v_error  : signed(63 downto 0);
        begin
            -- Apply input and hold it stable throughout pipeline
            win <= input_val;
            
            -- Wait for pipeline to process
            wait_cycles(PIPE_LATENCY);
            
            -- Read output
            v_result := lnout;
            v_error := v_result - expected;
            
            write(l, string'("TEST: "));
            write(l, label_str);
            write(l, string'("  Input=0x"));
            hwrite(l, std_logic_vector(input_val));
            writeline(output, l);
            
            write(l, string'("  Output=0x"));
            hwrite(l, std_logic_vector(v_result));
            write(l, string'("  Expected=0x"));
            hwrite(l, std_logic_vector(expected));
            writeline(output, l);
            
            write(l, string'("  Error=0x"));
            hwrite(l, std_logic_vector(v_error));
            -- Convert to approximate decimal error
            write(l, string'("  (Error int part: "));
            write(l, to_integer(v_error(63 downto 48)));
            write(l, string'(")"));
            writeline(output, l);
            writeline(output, l); -- blank line
        end procedure;
        
    begin
        -- Reset
        rst <= '1';
        wait_cycles(5);
        rst <= '0';
        wait_cycles(5);

        report "--- tb_customln: Starting Tests ---";

        test_value(VAL_0_5,  EXP_LN_0_5,  "-ln(0.5) ");
        test_value(VAL_0_25, EXP_LN_0_25, "-ln(0.25)");
        test_value(VAL_0_1,  EXP_LN_0_1,  "-ln(0.1) ");
        test_value(VAL_0_75, EXP_LN_0_75, "-ln(0.75)");
        test_value(VAL_0_9,  EXP_LN_0_9,  "-ln(0.9) ");

        report "--- tb_customln: All Tests Done ---";
        
        wait for 100 ns;
        std.env.stop;
    end process;

end architecture behavioral;
