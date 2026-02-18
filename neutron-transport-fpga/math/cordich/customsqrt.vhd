library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.config.all;
use work.configcordic.all;

----------------------------------------------------------------------------------
-- Entity: customsqrt
-- Description: 
--   Square Root using CORDIC Hyperbolic in Vectoring Mode.
--   Computes sqrt(x) for Q16.48 fixed-point numbers.
--   
-- Algorithm:
--   CORDIC Hyperbolic Vectoring Mode:
--   Given input a, set:
--     x_in = a + 0.25
--     y_in = a - 0.25
--     z_in = 0
--   
--   After CORDIC iterations in vectoring mode:
--     x_out ≈ K_h * sqrt(a)
--   
--   Where K_h ≈ 0.8281593609602478 is the hyperbolic CORDIC gain.
--   
--   To get sqrt(a): sqrt(a) = x_out / K_h
--
-- Latency: 
--   m_maxiterh + 3 cycles (CORDIC pipeline + input/output stages)
----------------------------------------------------------------------------------
entity customsqrt is
    port (
        clk      : in  std_logic;
        rst      : in  std_logic;
        
        x_in     : in  signed(length-1 downto 0); -- Input in Q16.48
        
        sqrt_out : out signed(length-1 downto 0)  -- Output in Q16.48
    );
end entity customsqrt;

architecture rtl of customsqrt is
    
    -- CORDIC Hyperbolic Component
    component cordich is
        generic (
            mode : cordicmode_t := m_vectoring
        );
        port (
            clk      : in  std_logic;
            rst      : in  std_logic;
            statein  : in  cordicstate_t;
            stateout : out cordicstate_t
        );
    end component;
    
    -- Constants in Q16.48
    constant QUARTER_Q16_48 : signed(length-1 downto 0) := x"0000400000000000"; -- 0.25
    constant ONE_Q16_48     : signed(length-1 downto 0) := x"0001000000000000"; -- 1.0
    
    -- Inverse of hyperbolic CORDIC gain K_h ≈ 1.20749 (1/0.8281593609602478)
    -- In Q16.48: 1.20749 * 2^48 ≈ 0x00013A850C1C8B1C
    constant INV_KH_Q16_48 : signed(length-1 downto 0) := x"00013A850C1C8B1C";
    
    -- Pipeline signals
    signal cordic_in  : cordicstate_t;
    signal cordic_out : cordicstate_t;
    
    -- Input/output pipeline registers
    signal x_reg      : signed(length-1 downto 0);
    signal x_plus_q   : signed(length-1 downto 0); -- a + 0.25
    signal x_minus_q  : signed(length-1 downto 0); -- a - 0.25
    
    signal cordic_result : signed(length-1 downto 0);
    signal scaled_result : signed(2*length-1 downto 0);
    
begin

    -- Instantiate CORDIC Hyperbolic in Vectoring Mode
    inst_cordich : cordich
        generic map (
            mode => m_vectoring
        )
        port map (
            clk      => clk,
            rst      => rst,
            statein  => cordic_in,
            stateout => cordic_out
        );
    
    -- Input Stage: Prepare CORDIC inputs
    process(clk, rst)
    begin
        if rst = '1' then
            x_reg <= (others => '0');
            x_plus_q <= (others => '0');
            x_minus_q <= (others => '0');
            cordic_in.x <= (others => '0');
            cordic_in.y <= (others => '0');
            cordic_in.z <= (others => '0');
            
        elsif rising_edge(clk) then
            -- Stage 1: Register input
            x_reg <= x_in;
            
            -- Stage 2: Compute x+0.25 and x-0.25
            x_plus_q  <= x_reg + QUARTER_Q16_48;
            x_minus_q <= x_reg - QUARTER_Q16_48;
            
            -- Stage 3: Feed to CORDIC
            -- For sqrt(a): x_in = a + 0.25, y_in = a - 0.25, z_in = 0
            cordic_in.x <= x_plus_q;
            cordic_in.y <= x_minus_q;
            cordic_in.z <= (others => '0');
        end if;
    end process;
    
    -- Output Stage: Scale by 1/K_h to get final sqrt
    process(clk, rst)
        variable v_product : signed(2*length-1 downto 0);
    begin
        if rst = '1' then
            cordic_result <= (others => '0');
            scaled_result <= (others => '0');
            sqrt_out <= (others => '0');
            
        elsif rising_edge(clk) then
            -- Stage N: Get CORDIC output (x component contains K_h * sqrt(a))
            cordic_result <= cordic_out.x;
            
            -- Stage N+1: Multiply by 1/K_h to get sqrt(a)
            -- Q16.48 * Q16.48 = Q32.96, then extract Q16.48
            v_product := cordic_result * INV_KH_Q16_48;
            scaled_result <= v_product;
            
            -- Stage N+2: Output final result
            -- Extract Q16.48 from Q32.96 (shift right by 48 bits)
            sqrt_out <= scaled_result(length+47 downto 48);
        end if;
    end process;

end architecture rtl;
