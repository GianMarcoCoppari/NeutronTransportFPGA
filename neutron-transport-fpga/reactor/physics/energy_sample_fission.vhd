--! @file energy_sample_fission.vhd
--! @brief Energy sampling module for fission neutrons using Watt spectrum (Binary Search)
--! @author Gian Marco Coppari
--! @date 2026-02-24
--! @details
--! Samples energy for prompt fission neutrons using binary search on CDF table.
--! Architecture similar to xs_lookup.vhd for consistency.
--!
--! **Algorithm:**
--! 1. Binary search: Find index i where ROM_CDF[i] < ξ < ROM_CDF[i+1]
--! 2. Interpolate: E = ROM_ENERGY[i] + (ξ - CDF[i]) × (E[i+1] - E[i]) / (CDF[i+1] - CDF[i])
--!
--! **Performance:**
--! - Latency: ~77 cycles (log₂(256) binary search + interpolation)
--! - Throughput: 1 sample/cycle (fully pipelined)
--!
--! **Data Format:**
--! - Input: 64-bit uniform random number ξ ∈ [0,1) in Q0.64
--! - Output: Energy in Q16.48 format (MeV)

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use ieee.std_logic_textio.all;
use work.config.all;
use work.fission_spectrum_rom.all;

--! @brief Energy sampling entity for fission neutrons
entity energy_sample_fission is
    port (
        clk         : in  std_logic;      --! Clock signal
        rst         : in  std_logic;      --! Asynchronous reset (active high)
        
        -- Input from PRNG
        rnd_in      : in  unsigned(63 downto 0);  --! Random number ξ [0,1) in Q0.64
        valid_in    : in  std_logic;              --! Input validity signal
        
        -- Output
        energy_out  : out unsigned(63 downto 0);  --! Sampled energy Q16.48 (MeV)
        valid_out   : out std_logic               --! Output validity signal
    );
end entity energy_sample_fission;

architecture behavioral of energy_sample_fission is

    constant ROM_SIZE : integer := get_fission_rom_size;
    
    -- Binary search signals
    signal bsearch_rom_addr  : integer range 0 to ROM_SIZE-1;
    signal bsearch_rom_data  : unsigned(63 downto 0);
    signal bsearch_result_idx: integer range 0 to ROM_SIZE-1;
    signal bsearch_valid_out : std_logic;

    -- ROM fetch stage
    signal fetch_valid    : std_logic;
    signal fetch_xi       : unsigned(63 downto 0);  -- Original ξ value
    signal fetch_idx_lo   : integer range 0 to ROM_SIZE-1;
    signal fetch_idx_hi   : integer range 0 to ROM_SIZE-1;
    
    -- ROM boundary values as mathematical points (CDF, Energy)
    signal point_lower : point_t;  -- (CDF[i], E[i])
    signal point_upper : point_t;  -- (CDF[i+1], E[i+1])
    
    -- Interpolation signals
    signal interp_query     : unsigned(63 downto 0);  -- ξ value for interpolation
    signal interp_valid_in  : std_logic;
    signal interp_valid_out : std_logic;
    signal interp_result    : unsigned(63 downto 0);  -- Interpolated energy

    -- Components
    component binarysearch is
        generic (
            ROM_SIZE : integer := 64
        );
        port (
            clk       : in  std_logic;
            rst       : in  std_logic;
            key_in    : in  unsigned(63 downto 0);
            valid_in  : in  std_logic;
            rom_addr  : out integer range 0 to ROM_SIZE-1;
            rom_data  : in  unsigned(63 downto 0);
            result_index : out integer range 0 to ROM_SIZE-1;
            valid_out    : out std_logic
        );
    end component;

    component lspline is
        port (
            clk       : in  std_logic;
            rst       : in  std_logic;
            p0_in     : in  point_t;
            p1_in     : in  point_t;
            x_query   : in  unsigned(63 downto 0);
            valid_in  : in  std_logic;
            y_out     : out unsigned(63 downto 0);
            valid_out : out std_logic
        );
    end component;

begin

    -- =========================================================================
    -- 1. Binary Search Instance
    -- =========================================================================
    inst_bsearch : binarysearch
        generic map (
            ROM_SIZE => ROM_SIZE
        )
        port map (
            clk       => clk,
            rst       => rst,
            key_in    => rnd_in,  -- Search for ξ value
            valid_in  => valid_in,
            rom_addr  => bsearch_rom_addr,
            rom_data  => bsearch_rom_data,
            result_index => bsearch_result_idx,
            valid_out => bsearch_valid_out
        );
    
    -- Provide ROM_CDF data to binary search
    bsearch_rom_data <= ROM_FISSION_CDF(bsearch_rom_addr);

    -- =========================================================================
    -- 2. ROM Boundary Fetch Stage
    -- =========================================================================
    process(clk)
        variable v_idx_lo : integer range 0 to ROM_SIZE-1;
        variable v_idx_hi : integer range 0 to ROM_SIZE-1;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                fetch_valid <= '0';
                fetch_xi <= (others => '0');
                fetch_idx_lo <= 0;
                fetch_idx_hi <= 0;
            else
                fetch_valid <= bsearch_valid_out;
                fetch_xi <= rnd_in;  -- Propagate original ξ
                
                if bsearch_valid_out = '1' then
                    v_idx_lo := bsearch_result_idx;
                    
                    -- Boundary check for upper index
                    if v_idx_lo >= ROM_SIZE - 1 then
                        v_idx_hi := ROM_SIZE - 1;
                        v_idx_lo := ROM_SIZE - 2;  -- Use last two points
                    else
                        v_idx_hi := v_idx_lo + 1;
                    end if;
                    
                    fetch_idx_lo <= v_idx_lo;
                    fetch_idx_hi <= v_idx_hi;
                else
                    fetch_idx_lo <= 0;
                    fetch_idx_hi <= 0;
                end if;
            end if;
        end if;
    end process;

    -- =========================================================================
    -- 3. ROM Data Fetch
    -- =========================================================================
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                interp_valid_in <= '0';
                interp_query    <= (others => '0');
                point_lower.x   <= (others => '0');
                point_lower.y   <= (others => '0');
                point_upper.x   <= (others => '0');
                point_upper.y   <= (others => '0');
            else
                interp_valid_in <= fetch_valid;
                interp_query    <= fetch_xi;
                
                if fetch_valid = '1' then
                    -- Lower bound point: (CDF[i], E[i])
                    point_lower.x <= ROM_FISSION_CDF(fetch_idx_lo);
                    point_lower.y <= ROM_FISSION_ENERGY(fetch_idx_lo);
                    
                    -- Upper bound point: (CDF[i+1], E[i+1])
                    point_upper.x <= ROM_FISSION_CDF(fetch_idx_hi);
                    point_upper.y <= ROM_FISSION_ENERGY(fetch_idx_hi);
                end if;
            end if;
        end if;
    end process;

    -- =========================================================================
    -- 4. Linear Interpolation Instance
    -- =========================================================================
    inst_interp : lspline
        port map (
            clk       => clk,
            rst       => rst,
            p0_in     => point_lower,   -- (CDF[i], E[i])
            p1_in     => point_upper,   -- (CDF[i+1], E[i+1])
            x_query   => interp_query,  -- ξ value
            valid_in  => interp_valid_in,
            y_out     => interp_result, -- E(ξ) interpolated
            valid_out => interp_valid_out
        );

    -- =========================================================================
    -- 5. Output Assignment
    -- =========================================================================
    valid_out  <= interp_valid_out;
    energy_out <= interp_result;

end architecture behavioral;
