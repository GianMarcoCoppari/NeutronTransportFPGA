library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.config.all;

entity tb_divr2 is
end tb_divr2;

architecture tb of tb_divr2 is

    component divr2
        port (
            clk      : in  std_logic;
            rst      : in  std_logic;
            dividend : in  unsigned(length-1 downto 0);
            divisor  : in  unsigned(length-1 downto 0);
            quotient : out unsigned(length-1 downto 0)
        );
    end component;

    signal clk : std_logic := '0';
    signal rst : std_logic := '1';
    signal dividend : unsigned(length-1 downto 0) := (others => '0');
    signal divisor  : unsigned(length-1 downto 0) := (others => '0');
    signal quotient : unsigned(length-1 downto 0);
    
    constant CLK_PERIOD : time := 10 ns;
    
    type test_pair is record
        n : unsigned(length-1 downto 0);
        d : unsigned(length-1 downto 0);
    end record;
    
    -- Helper to create unsigned from integer, handling length constraint
    function u(val : integer) return unsigned is 
    begin 
        return to_unsigned(val, length);
    end function;

    -- Using array of test cases
    type test_array is array (natural range <>) of test_pair;
    constant TESTS : test_array := (
        (u(100), u(2)),     -- 50
        (u(100), u(3)),     -- 33
        (u(1000), u(10)),   -- 100
        (u(123456), u(123)),-- 1003
        (u(1), u(1)),       -- 1
        (u(0), u(5)),       -- 0
        (u(50), u(100))     -- 0
    );

begin

    uut : divr2
        port map (
            clk => clk,
            rst => rst,
            dividend => dividend,
            divisor => divisor,
            quotient => quotient
        );

    -- Clock generation
    clk_process : process
    begin
        clk <= '0';
        wait for CLK_PERIOD/2;
        clk <= '1';
        wait for CLK_PERIOD/2;
    end process;

    -- Stimulus and Check process
    stim_check : process
        variable expected_q : unsigned(length-1 downto 0);
        variable actual_q : unsigned(length-1 downto 0);
    begin
        -- Reset
        rst <= '1';
        wait for CLK_PERIOD * 5;
        rst <= '0';
        wait until rising_edge(clk);

        report "Starting Division Tests...";

        -- We have a pipeline of depth 'length'.
        -- Strategy: Feed checking routine into a delayed procedure or use a queue?
        -- For simplicity in VHDL checks without complex structures:
        -- Feed all inputs, then wait for latency, then check?
        -- No, with pipeline, outputs come out in same order.
        
        -- Since verification needs inputs to compare against, and they are delayed by 'length'.
        -- We will execute loop twice: once to feed, once to check with delay?
        -- Better: run feeding in one process, checking in another?
        -- No, I'll stick to a simple lock-step or array-based approach if input count is low.
        
        -- Let's use a dual-process approach with strict timing if I was sure, but simple loop with queue is better.
        -- Given VHDL constraints, I'll launch inputs, and have a separate tracking index for checking.
        
        -- Phase 1: Injection
        for i in TESTS'range loop
            dividend <= TESTS(i).n;
            divisor  <= TESTS(i).d;
            wait for CLK_PERIOD;
        end loop;
        
        dividend <= (others => '0');
        divisor  <= (others => '1'); -- Dummy
        
        -- Wait for the rest of pipeline to drain the remaining valid results
        -- We just injected TESTS'length items.
        -- The first item comes out at cycle 'length' after insertion.
        -- We inserted them at cycles T, T+1, ...
        -- So output valid at T+length, T+length+1, ...
        
        wait for CLK_PERIOD * length; -- Wait for latency of first item - (already passed cycles?)
        -- Actually we need to align carefully. 
        wait;
    end process;
    
    -- Dedicated check process to decouple timing
    check_process : process
        variable v_expected : unsigned(length-1 downto 0);
        variable k_idx : integer := 0; -- Renamed loop variable
    begin
        -- Initial Wait for Latency
        -- Reset phase
        wait until rst = '0';
        wait until rising_edge(clk); -- Sync with first input injection
        
        -- Wait strictly 'length' cycles
        for k in 1 to length loop
            wait until rising_edge(clk);
        end loop;
        
        -- Now Check Loop
        for k_idx in TESTS'range loop
             -- Wait for half cycle to sample stable output (middle of valid window)
             wait until falling_edge(clk);
             
             -- Compute expected
             if TESTS(k_idx).d = 0 then
                 v_expected := (others => '1'); -- Saturation assumption
             else 
                 v_expected := TESTS(k_idx).n / TESTS(k_idx).d;
             end if;
             
             assert quotient = v_expected
                 report "Mismatch at index " & integer'image(k_idx) & 
                        " Exp: " & to_hstring(v_expected) &
                        " Got: " & to_hstring(quotient)
                 severity error;
                 
             if quotient = v_expected then
                 report "Test " & integer'image(k_idx) & " PASS";
             end if;
             
             -- Note: Next loop iteration will wait for next falling edge, keeping 1 cycle pace.
        end loop; 
        
        report "All tests finished.";
        std.env.stop;
    end process;

end tb;
