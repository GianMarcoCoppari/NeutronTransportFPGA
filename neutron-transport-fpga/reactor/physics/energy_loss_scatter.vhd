--! @file energy_loss_scatter.vhd
--! @brief Energy loss calculation for elastic scattering
--! @author Gian Marco Coppari
--! @date 2026-02-24
--! @details
--! Calculates energy loss for neutron elastic scattering using a simplified
--! free-gas scattering model. For isotropic scattering in the center-of-mass frame,
--! the energy reduction factor α is uniformly distributed in [α_min, 1].
--!
--! **Physics Model:**
--! E_out = E_in × α
--! where α ∈ [α_min, 1]
--! and α_min = [(A-1)/(A+1)]²
--! with A = atomic mass number of target nucleus
--!
--! **Typical Values:**
--! - Hydrogen (A=1):    α_min = 0.000 (max energy loss)
--! - Carbon (A=12):     α_min = 0.716
--! - Oxygen (A=16):     α_min = 0.779
--! - Uranium (A=238):   α_min = 0.983 (minimal energy loss)
--!
--! **Algorithm:**
--! 1. Map random number ξ ∈ [0,1) to α:  α = α_min + ξ × (1 - α_min)
--! 2. Multiply: E_out = E_in × α (Q16.48 × Q0.64 → Q16.48)
--!
--! **Performance:**
--! - Latency: ~5-6 cycles (multiplication + scaling)
--! - Throughput: 1 scatter/cycle (fully pipelined)

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.config.all;
use work.configopenmc.all;
use std.textio.all;
use ieee.std_logic_textio.all;

--! @brief Energy loss entity for elastic scattering
entity energy_loss_scatter is
    generic (
        -- Pre-computed α_min for different materials (Q0.64 format)
        -- Default: Uranium-235 (α_min ≈ 0.983)
        ALPHA_MIN : unsigned(63 downto 0) := x"FB90000000000000"  -- 0.983 U-235
    );
    port (
        clk         : in  std_logic;      --! Clock signal
        rst         : in  std_logic;      --! Asynchronous reset (active high)
        
        -- Input
        E_in        : in  unsigned(63 downto 0);  --! Incident energy Q16.48 (MeV)
        rnd_in      : in  unsigned(63 downto 0);  --! Random number [0,1) in Q0.64
        valid_in    : in  std_logic;              --! Input validity signal
        
        -- Output
        E_out       : out unsigned(63 downto 0);  --! Scattered energy Q16.48 (MeV)
        valid_out   : out std_logic               --! Output validity signal
    );
end entity energy_loss_scatter;

architecture behavioral of energy_loss_scatter is

    -- Pipeline stages
    constant LATENCY : integer := 6;
    
    -- Constants in Q0.64 format
    constant ONE_Q0_64 : unsigned(63 downto 0) := x"FFFFFFFFFFFFFFFF";
    
    -- Stage 0: Input registers
    signal s0_E_in     : unsigned(63 downto 0);
    signal s0_rnd      : unsigned(63 downto 0);
    signal s0_valid    : std_logic;
    
    -- Stage 1: Calculate (1 - α_min)
    signal s1_one_minus_alpha_min : unsigned(63 downto 0);
    signal s1_E_in                : unsigned(63 downto 0);
    signal s1_rnd                 : unsigned(63 downto 0);
    signal s1_valid               : std_logic;
    
    -- Stage 2: Calculate ξ × (1 - α_min)
    signal s2_xi_delta : unsigned(127 downto 0);  -- Full product
    signal s2_E_in     : unsigned(63 downto 0);
    signal s2_valid    : std_logic;
    
    -- Stage 3: Calculate α = α_min + ξ × (1 - α_min)
    signal s3_alpha    : unsigned(63 downto 0);  -- Q0.64
    signal s3_E_in     : unsigned(63 downto 0);
    signal s3_valid    : std_logic;
    
    -- Stage 4-5: Multiply E_in × α
    signal s4_product  : unsigned(127 downto 0);  -- Q16.112
    signal s4_valid    : std_logic;
    
    signal s5_E_out    : unsigned(63 downto 0);   -- Q16.48
    signal s5_valid    : std_logic;
    
    -- Debug pipelines for temporally aligned logging
    type E_in_pipe_t is array (0 to 5) of unsigned(63 downto 0);
    signal E_in_pipe : E_in_pipe_t;
    type alpha_pipe_t is array (0 to 2) of unsigned(63 downto 0);
    signal alpha_pipe : alpha_pipe_t;

begin

    -- =========================================================================
    -- Main Pipeline Process
    -- =========================================================================
    process(clk, rst)
        variable v_one_minus_alpha : unsigned(63 downto 0);
        variable v_xi_delta_full   : unsigned(127 downto 0);
        variable v_xi_delta_scaled : unsigned(63 downto 0);
        variable v_alpha           : unsigned(127 downto 0);
        variable v_product_full    : unsigned(127 downto 0);
        variable v_E_out_scaled    : unsigned(63 downto 0);
    begin
        if rst = '1' then
            -- Reset all pipeline stages
            s0_E_in <= (others => '0');
            s0_rnd  <= (others => '0');
            s0_valid <= '0';
            
            s1_one_minus_alpha_min <= (others => '0');
            s1_E_in <= (others => '0');
            s1_rnd  <= (others => '0');
            s1_valid <= '0';
            
            s2_xi_delta <= (others => '0');
            s2_E_in     <= (others => '0');
            s2_valid    <= '0';
            
            s3_alpha <= (others => '0');
            s3_E_in  <= (others => '0');
            s3_valid <= '0';
            
            s4_product <= (others => '0');
            s4_valid   <= '0';
            
            s5_E_out <= (others => '0');
            s5_valid <= '0';
            
            E_out <= (others => '0');
            valid_out <= '0';
            
        elsif rising_edge(clk) then
            
            -- Stage 0: Input sampling
            s0_E_in  <= E_in;
            s0_rnd   <= rnd_in;
            s0_valid <= valid_in;
            
            -- Stage 1: Calculate (1 - α_min)
            -- Since α_min is Q0.64 and we want (1 - α_min) in Q0.64
            -- We need to subtract from 1.0 represented as 0xFFFFFFFFFFFFFFFF
            v_one_minus_alpha := ONE_Q0_64 - ALPHA_MIN;
            
            s1_one_minus_alpha_min <= v_one_minus_alpha;
            s1_E_in <= s0_E_in;
            s1_rnd  <= s0_rnd;
            s1_valid <= s0_valid;
            
            -- Stage 2: Calculate ξ × (1 - α_min)
            -- Both are Q0.64, product is Q0.128
            v_xi_delta_full := s1_rnd * s1_one_minus_alpha_min;
            
            s2_xi_delta <= v_xi_delta_full;
            s2_E_in     <= s1_E_in;
            s2_valid    <= s1_valid;
            
            -- Stage 3: Calculate α = α_min + ξ × (1 - α_min)
            -- α_min is Q0.64, ξ×(1-α_min) is Q0.128
            -- Extract Q0.64 from Q0.128: take upper 64 bits [127:64]
            v_xi_delta_scaled := s2_xi_delta(127 downto 64);
            
            -- Add: both in Q0.64
            v_alpha := resize(ALPHA_MIN, 128) + resize(v_xi_delta_scaled, 128);
            
            -- Clamp to [0, 1] (should not exceed, but safety check)
            if v_alpha(127 downto 64) /= 0 then
                s3_alpha <= ONE_Q0_64;  -- Saturate to 1.0
            else
                s3_alpha <= v_alpha(63 downto 0);
            end if;
            
            s3_E_in  <= s2_E_in;
            s3_valid <= s2_valid;
            
            -- Stage 4: Multiply E_in × α
            -- E_in is Q16.48, α is Q0.64
            -- Product is Q16.112
            v_product_full := s3_E_in * s3_alpha;
            
            s4_product <= v_product_full;
            s4_valid   <= s3_valid;
            
            -- Stage 5: Scale back to Q16.48
            -- s4_product is Q16.112 (16 int bits + 112 frac bits) = unsigned(127 downto 0)
            -- Extract Q16.48: take bits [127:64] (16 int + 48 frac = 64 bits total)
            s5_E_out <= s4_product(127 downto 64);
            s5_valid <= s4_valid;
            
            -- Stage 6: Output with debug
            E_out     <= s5_E_out;
            valid_out <= s5_valid;
            
            -- Debug: Print energy degradation (with temporally aligned values)
            if s5_valid = '1' then
                report "SCATTER_ENERGY_LOSS: E_in=" & to_hstring(E_in_pipe(5)) &
                       " E_out=" & to_hstring(s5_E_out) &
                       " alpha=" & to_hstring(alpha_pipe(2)) &
                       " ratio=" & to_hstring(resize(shift_right(s5_E_out & x"0000000000000000", 48) /
                                                     (E_in_pipe(5) + 1), 64));
            end if;
            
        end if;
    end process;

end architecture behavioral;
