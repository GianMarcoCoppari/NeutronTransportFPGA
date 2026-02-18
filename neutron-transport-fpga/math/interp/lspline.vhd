library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.config.all;

----------------------------------------------------------------------------------
-- Entity: lspline
-- Description:
--   Linear spline (piecewise linear) interpolation module.
--   Computes: y = f(x) using linear interpolation between two points
--   
--   Formula: y = y₀ + (y₁ - y₀) × (x - x₀) / (x₁ - x₀)
--   
-- Algorithm:
--   1. Compute Δx = x₁ - x₀
--   2. Compute Δy = y₁ - y₀  
--   3. Compute offset = x - x₀
--   4. Compute fraction = offset / Δx  (using divr2 hardware divider)
--   5. Compute result = y₀ + fraction × Δy
--   
-- Pipeline Stages:
--   Stage 0: Input register
--   Stage 1: Compute deltas (Δx, Δy, offset)
--   Stage 2-65: Hardware division (divr2, 64 cycles)
--   Stage 66: Compute product (fraction × Δy)
--   Stage 67: Add y₀ + product
--   Stage 68: Output register
--
-- Total Latency: 69 cycles
--
-- Note: All values are Q16.48 fixed-point format
----------------------------------------------------------------------------------
entity lspline is
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;
        
        -- Input: Two interpolation points (p₀, p₁) and query x
        p0_in     : in  point_t;   -- Point 0: (x₀, y₀)
        p1_in     : in  point_t;   -- Point 1: (x₁, y₁)
        x_query   : in  unsigned(length-1 downto 0);  -- Query point x
        valid_in  : in  std_logic;
        
        -- Output: Interpolated result y = f(x_query)
        y_out     : out unsigned(length-1 downto 0);  -- Interpolated value
        valid_out : out std_logic
    );
end entity lspline;

architecture rtl of lspline is
    
    -- Hardware divider component
    component divr2 is
        port (
            clk      : in  std_logic;
            rst      : in  std_logic;
            dividend : in  unsigned(length-1 downto 0);
            divisor  : in  unsigned(length-1 downto 0);
            quotient : out unsigned(length-1 downto 0)
        );
    end component;
    
    -- Constants
    constant DIV_LATENCY : integer := length;  -- 64 cycles for 64-bit divider
    
    -- Stage 0: Input registers (mathematical notation)
    type input_stage_t is record
        valid : std_logic;
        p0    : point_t;  -- Lower bound point
        p1    : point_t;  -- Upper bound point
        x     : unsigned(length-1 downto 0);  -- Query x-coordinate
    end record;
    signal stage_input : input_stage_t;
    
    -- Stage 1: Computed deltas (mathematical increments)
    type delta_stage_t is record
        valid : std_logic;
        y0    : unsigned(length-1 downto 0);  -- Reference value
        delta_x    : unsigned(length-1 downto 0);  -- x₁ - x₀
        delta_y    : signed(length-1 downto 0);    -- y₁ - y₀ (signed for slopes)
        dx    : unsigned(length-1 downto 0);  -- x - x₀ (offset from p0)
    end record;
    signal stage_delta : delta_stage_t;
    
    -- Divider interface (fraction = dx / Δx)
    signal div_dividend : unsigned(length-1 downto 0);  -- Numerator: dx
    signal div_divisor  : unsigned(length-1 downto 0);  -- Denominator: Δx
    signal div_quotient : unsigned(length-1 downto 0);  -- Result: fraction ∈ [0,1]
    
    -- Pipeline delay registers (propagate through divider latency)
    type delay_array_t is array (0 to DIV_LATENCY) of unsigned(length-1 downto 0);
    signal y0_delayed : delay_array_t;  -- y₀ propagation
    
    type delay_array_signed_t is array (0 to DIV_LATENCY) of signed(length-1 downto 0);
    signal delta_y_delayed : delay_array_signed_t;  -- Δy propagation
    
    type delay_array_valid_t is array (0 to DIV_LATENCY) of std_logic;
    signal valid_delayed : delay_array_valid_t;  -- Valid propagation
    
    -- Stage DIV+2: Product stage (fraction × Δy)
    signal product_stage_valid  : std_logic;
    signal product_stage_y0     : unsigned(length-1 downto 0);
    signal product_stage_result : signed(length-1 downto 0);  -- fraction × Δy
    
    -- Stage DIV+3: Sum stage (y₀ + product)
    signal sum_stage_valid  : std_logic;
    signal sum_stage_result : unsigned(length-1 downto 0);

begin

    -- =========================================================================
    -- Stage 0: Input Register
    -- =========================================================================
    -- Captures interpolation problem: given p₀=(x₀,y₀), p₁=(x₁,y₁), find y(x)
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                stage_input.valid <= '0';
                stage_input.p0.x  <= (others => '0');
                stage_input.p0.y  <= (others => '0');
                stage_input.p1.x  <= (others => '0');
                stage_input.p1.y  <= (others => '0');
                stage_input.x     <= (others => '0');
            else
                stage_input.valid <= valid_in;
                stage_input.p0    <= p0_in;
                stage_input.p1    <= p1_in;
                stage_input.x     <= x_query;
            end if;
        end if;
    end process;

    -- =========================================================================
    -- Stage 1: Compute Deltas (Finite Differences)
    -- =========================================================================
    -- Calculate: Δx = x₁ - x₀, Δy = y₁ - y₀, dx = x - x₀
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                stage_delta.valid <= '0';
                stage_delta.y0    <= (others => '0');
                stage_delta.delta_x    <= (others => '0');
                stage_delta.delta_y    <= (others => '0');
                stage_delta.dx    <= (others => '0');
            else
                stage_delta.valid <= stage_input.valid;
                
                if stage_input.valid = '1' then
                    -- Compute x-interval width: Δx = x₁ - x₀
                    stage_delta.delta_x <= stage_input.p1.x - stage_input.p0.x;
                    
                    -- Compute y-interval height: Δy = y₁ - y₀ (signed for negative slopes)
                    stage_delta.delta_y <= signed(stage_input.p1.y) - signed(stage_input.p0.y);
                    
                    -- Compute query offset from lower bound: dx = x - x₀
                    stage_delta.dx <= stage_input.x - stage_input.p0.x;
                    
                    -- Propagate reference value y₀
                    stage_delta.y0 <= stage_input.p0.y;
                else
                    stage_delta.delta_x <= (others => '0');
                    stage_delta.delta_y <= (others => '0');
                    stage_delta.dx <= (others => '0');
                    stage_delta.y0 <= (others => '0');
                end if;
            end if;
        end if;
    end process;

    -- =========================================================================
    -- Stage 2: Feed Hardware Divider
    -- =========================================================================
    -- Compute fraction ξ = dx / Δx ∈ [0, 1]
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                div_dividend <= (others => '0');
                div_divisor  <= (others => '0');
            else
                if stage_delta.valid = '1' then
                    div_dividend <= stage_delta.dx;   -- Numerator: x - x₀
                    div_divisor  <= stage_delta.delta_x;   -- Denominator: x₁ - x₀
                else
                    div_dividend <= (others => '0');
                    div_divisor  <= to_unsigned(1, length);  -- Avoid division by zero
                end if;
            end if;
        end if;
    end process;

    -- =========================================================================
    -- Stages 3-66: Hardware Divider Pipeline (divr2)
    -- =========================================================================
    -- Computes ξ = dx / Δx with 64-cycle pipelined radix-2 division
    inst_divider : divr2
        port map (
            clk      => clk,
            rst      => rst,
            dividend => div_dividend,
            divisor  => div_divisor,
            quotient => div_quotient  -- Output: fraction ξ
        );

    -- =========================================================================
    -- Parallel: Delay Registers (align data with divider output)
    -- =========================================================================
    -- Propagate y₀, Δy, and valid through 64-cycle divider latency
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                y0_delayed <= (others => (others => '0'));
                delta_y_delayed <= (others => (others => '0'));
                valid_delayed <= (others => '0');
            else
                -- Shift register for y₀ (reference value)
                y0_delayed(0) <= stage_delta.y0;
                for i in 0 to DIV_LATENCY-1 loop
                    y0_delayed(i+1) <= y0_delayed(i);
                end loop;
                
                -- Shift register for Δy (slope)
                delta_y_delayed(0) <= stage_delta.delta_y;
                for i in 0 to DIV_LATENCY-1 loop
                    delta_y_delayed(i+1) <= delta_y_delayed(i);
                end loop;
                
                -- Shift register for valid signal
                valid_delayed(0) <= stage_delta.valid;
                for i in 0 to DIV_LATENCY-1 loop
                    valid_delayed(i+1) <= valid_delayed(i);
                end loop;
            end if;
        end if;
    end process;

    -- =========================================================================
    -- Stage 67: Compute Interpolation Term (ξ × Δy)
    -- =========================================================================
    -- Multiply fraction by slope to get interpolation offset
    process(clk)
        variable v_product : signed(2*length-1 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                product_stage_valid  <= '0';
                product_stage_y0     <= (others => '0');
                product_stage_result <= (others => '0');
            else
                product_stage_valid <= valid_delayed(DIV_LATENCY);
                product_stage_y0    <= y0_delayed(DIV_LATENCY);
                
                if valid_delayed(DIV_LATENCY) = '1' then
                    -- Compute: ξ × Δy (fraction × slope)
                    -- Q16.48 × Q16.48 = Q32.96
                    v_product := signed(div_quotient) * delta_y_delayed(DIV_LATENCY);
                    
                    -- Extract Q16.48 from Q32.96 (divide by 2^48)
                    product_stage_result <= v_product(length+47 downto 48);
                else
                    product_stage_result <= (others => '0');
                end if;
            end if;
        end if;
    end process;

    -- =========================================================================
    -- Stage 68: Final Linear Combination (y₀ + ξ×Δy)
    -- =========================================================================
    -- Complete the linear interpolation formula
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                sum_stage_valid  <= '0';
                sum_stage_result <= (others => '0');
            else
                sum_stage_valid <= product_stage_valid;
                
                if product_stage_valid = '1' then
                    -- Final result: y = y₀ + ξ×Δy
                    sum_stage_result <= unsigned(
                        signed(product_stage_y0) + product_stage_result
                    );
                else
                    sum_stage_result <= (others => '0');
                end if;
            end if;
        end if;
    end process;

    -- =========================================================================
    -- Stage 69: Output Register
    -- =========================================================================
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                valid_out <= '0';
                y_out     <= (others => '0');
            else
                valid_out <= sum_stage_valid;
                y_out     <= sum_stage_result;
            end if;
        end if;
    end process;

end architecture rtl;
