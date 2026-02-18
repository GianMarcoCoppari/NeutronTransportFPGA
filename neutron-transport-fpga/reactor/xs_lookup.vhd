library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use ieee.std_logic_textio.all;
use work.config.all;
use work.xs_rom_small.all;

----------------------------------------------------------------------------------
-- Entity: xs_lookup
-- Description:
--   Cross section lookup with energy-dependent interpolation.
--   Composes binary search + linear interpolation modules.
--   
-- Architecture:
--   1. Binary search finds index i: E_ROM(i) <= E_particle < E_ROM(i+1)
--   2. Fetch boundary values from ROM: E_i, E_{i+1}, σ_i, σ_{i+1}
--   3. Linear interpolation computes σ(E_particle)
--   
-- Pipeline Stages:
--   0-N:   Binary search (N = log2(ROM_SIZE))
--   N+1:   Fetch ROM boundaries
--   N+2-70: Linear interpolation (69 stages with divr2 hardware divider)
--
-- Total Latency: log2(ROM_SIZE) + 71 cycles (~77 cycles for ROM_SIZE=64)
----------------------------------------------------------------------------------
entity xs_lookup is
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;
        
        -- Input
        energy_in : in  unsigned(length-1 downto 0);  -- Particle energy Q16.48
        valid_in  : in  std_logic;
        
        -- Output
        inv_sigma_out : out unsigned(length-1 downto 0); -- 1/σ_total Q16.48
        valid_out     : out std_logic
    );
end entity xs_lookup;

architecture behavioral of xs_lookup is

    constant ROM_SIZE : integer := ROM_ENERGY'length;

    -- Binary search signals
    signal bsearch_rom_addr  : integer range 0 to ROM_SIZE-1;
    signal bsearch_rom_data  : unsigned(length-1 downto 0);
    signal bsearch_result_idx: integer range 0 to ROM_SIZE-1;
    signal bsearch_valid_out : std_logic;

    -- ROM fetch stage
    signal fetch_valid    : std_logic;
    signal fetch_energy   : unsigned(length-1 downto 0);
    signal fetch_idx_lo   : integer range 0 to ROM_SIZE-1;
    signal fetch_idx_hi   : integer range 0 to ROM_SIZE-1;
    
    -- ROM boundary values as mathematical points
    signal point_lower : point_t;  -- (E_i, σ_i)
    signal point_upper : point_t;  -- (E_{i+1}, σ_{i+1})
    
    -- Interpolation signals
    signal interp_query     : unsigned(length-1 downto 0);
    signal interp_valid_in  : std_logic;
    signal interp_valid_out : std_logic;
    signal interp_result    : unsigned(length-1 downto 0);

    -- Components
    component binarysearch is
        generic (
            ROM_SIZE : integer := 64
        );
        port (
            clk       : in  std_logic;
            rst       : in  std_logic;
            key_in    : in  unsigned(length-1 downto 0);
            valid_in  : in  std_logic;
            rom_addr  : out integer range 0 to ROM_SIZE-1;
            rom_data  : in  unsigned(length-1 downto 0);
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
            x_query   : in  unsigned(length-1 downto 0);
            valid_in  : in  std_logic;
            y_out     : out unsigned(length-1 downto 0);
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
            key_in    => energy_in,
            valid_in  => valid_in,
            rom_addr  => bsearch_rom_addr,
            rom_data  => bsearch_rom_data,
            result_index => bsearch_result_idx,
            valid_out => bsearch_valid_out
        );
    
    -- Provide ROM data to binary search
    bsearch_rom_data <= ROM_ENERGY(bsearch_rom_addr);

    -- =========================================================================
    -- 2. ROM Boundary Fetch Stage
    -- =========================================================================
    -- After binary search completes, fetch boundary values for interpolation
    process(clk)
        variable v_idx_lo : integer range 0 to ROM_SIZE-1;
        variable v_idx_hi : integer range 0 to ROM_SIZE-1;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                fetch_valid <= '0';
                fetch_energy <= (others => '0');
                fetch_idx_lo <= 0;
                fetch_idx_hi <= 0;
            else
                fetch_valid <= bsearch_valid_out;
                fetch_energy <= energy_in; -- Propagate original energy
                
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
    -- Read boundary energies and cross sections from ROM
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
                interp_query    <= fetch_energy;
                
                if fetch_valid = '1' then
                    -- Lower bound point: (E_i, σ_i)
                    point_lower.x <= ROM_ENERGY(fetch_idx_lo);
                    point_lower.y <= ROM_INV_SIGMA_TOTAL(fetch_idx_lo);
                    
                    -- Upper bound point: (E_{i+1}, σ_{i+1})
                    point_upper.x <= ROM_ENERGY(fetch_idx_hi);
                    point_upper.y <= ROM_INV_SIGMA_TOTAL(fetch_idx_hi);
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
            p0_in     => point_lower,   -- (E_i, σ_i)
            p1_in     => point_upper,   -- (E_{i+1}, σ_{i+1})
            x_query   => interp_query,  -- E_particle
            valid_in  => interp_valid_in,
            y_out     => interp_result, -- σ(E_particle)
            valid_out => interp_valid_out
        );

    -- =========================================================================
    -- 5. Output Assignment
    -- =========================================================================
    valid_out     <= interp_valid_out;
    inv_sigma_out <= interp_result;

end architecture behavioral;
