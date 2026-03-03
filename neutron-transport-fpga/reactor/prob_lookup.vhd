library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use ieee.std_logic_textio.all;
use work.config.all;
use work.xs_rom_small.all;

----------------------------------------------------------------------------------
-- Entity: prob_lookup
-- Description:
--   Energy-dependent interaction probability lookup.
--   Given a particle energy, returns P_absorption(E) and P_fission(E)
--   using binary search on ROM_ENERGY + linear interpolation on ROM_PROB_*.
--   
-- Architecture:
--   1. Binary search finds index i: E_ROM(i) <= E_particle < E_ROM(i+1)
--   2. Fetch boundary values from ROM: E_i, E_{i+1}, P_i, P_{i+1}
--   3. Two parallel lspline instances interpolate P_abs and P_fiss
--   
-- Pipeline Stages:
--   0-N:   Binary search (N = log2(ROM_SIZE))
--   N+1:   Fetch ROM boundaries
--   N+2-70: Linear interpolation (69 stages with divr2 hardware divider)
--
-- Total Latency: log2(ROM_SIZE) + 71 cycles (~77 cycles for ROM_SIZE=64)
----------------------------------------------------------------------------------
entity prob_lookup is
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;
        
        -- Input
        energy_in : in  unsigned(63 downto 0);  -- Particle energy Q16.48
        valid_in  : in  std_logic;
        
        -- Output: Interaction probabilities (Q16.48, values in [0, 1])
        prob_abs_out  : out unsigned(63 downto 0); -- P_absorption(E)
        prob_fiss_out : out unsigned(63 downto 0); -- P_fission(E)
        valid_out     : out std_logic
    );
end entity prob_lookup;

architecture behavioral of prob_lookup is

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
    
    -- Interpolation points for P_absorption
    signal point_abs_lo : point_t;
    signal point_abs_hi : point_t;
    
    -- Interpolation points for P_fission
    signal point_fiss_lo : point_t;
    signal point_fiss_hi : point_t;
    
    -- Interpolation signals
    signal interp_query     : unsigned(length-1 downto 0);
    signal interp_valid_in  : std_logic;
    
    signal interp_abs_valid  : std_logic;
    signal interp_abs_result : unsigned(length-1 downto 0);
    
    signal interp_fiss_valid  : std_logic;
    signal interp_fiss_result : unsigned(length-1 downto 0);

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
    -- 1. Binary Search Instance (shared for both channels)
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
                fetch_energy <= energy_in;
                
                if bsearch_valid_out = '1' then
                    v_idx_lo := bsearch_result_idx;
                    
                    if v_idx_lo >= ROM_SIZE - 1 then
                        v_idx_hi := ROM_SIZE - 1;
                        v_idx_lo := ROM_SIZE - 2;
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
    -- 3. ROM Data Fetch (Absorption + Fission channels in parallel)
    -- =========================================================================
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                interp_valid_in <= '0';
                interp_query    <= (others => '0');
                point_abs_lo.x  <= (others => '0');
                point_abs_lo.y  <= (others => '0');
                point_abs_hi.x  <= (others => '0');
                point_abs_hi.y  <= (others => '0');
                point_fiss_lo.x <= (others => '0');
                point_fiss_lo.y <= (others => '0');
                point_fiss_hi.x <= (others => '0');
                point_fiss_hi.y <= (others => '0');
            else
                interp_valid_in <= fetch_valid;
                interp_query    <= fetch_energy;
                
                if fetch_valid = '1' then
                    -- Absorption channel
                    point_abs_lo.x <= ROM_ENERGY(fetch_idx_lo);
                    point_abs_lo.y <= ROM_PROB_ABSORPTION(fetch_idx_lo);
                    point_abs_hi.x <= ROM_ENERGY(fetch_idx_hi);
                    point_abs_hi.y <= ROM_PROB_ABSORPTION(fetch_idx_hi);
                    
                    -- Fission channel
                    point_fiss_lo.x <= ROM_ENERGY(fetch_idx_lo);
                    point_fiss_lo.y <= ROM_PROB_FISSION(fetch_idx_lo);
                    point_fiss_hi.x <= ROM_ENERGY(fetch_idx_hi);
                    point_fiss_hi.y <= ROM_PROB_FISSION(fetch_idx_hi);
                end if;
            end if;
        end if;
    end process;

    -- =========================================================================
    -- 4. Linear Interpolation: Absorption channel
    -- =========================================================================
    inst_interp_abs : lspline
        port map (
            clk       => clk,
            rst       => rst,
            p0_in     => point_abs_lo,
            p1_in     => point_abs_hi,
            x_query   => interp_query,
            valid_in  => interp_valid_in,
            y_out     => interp_abs_result,
            valid_out => interp_abs_valid
        );

    -- =========================================================================
    -- 5. Linear Interpolation: Fission channel
    -- =========================================================================
    inst_interp_fiss : lspline
        port map (
            clk       => clk,
            rst       => rst,
            p0_in     => point_fiss_lo,
            p1_in     => point_fiss_hi,
            x_query   => interp_query,
            valid_in  => interp_valid_in,
            y_out     => interp_fiss_result,
            valid_out => interp_fiss_valid
        );

    -- =========================================================================
    -- 6. Output Assignment
    -- =========================================================================
    -- Both lspline instances have identical latency, so either valid works
    valid_out     <= interp_abs_valid;
    prob_abs_out  <= interp_abs_result;
    prob_fiss_out <= interp_fiss_result;

end architecture behavioral;
