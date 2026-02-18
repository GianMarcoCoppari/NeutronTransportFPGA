library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.config.all;

----------------------------------------------------------------------------------
-- Entity: binarysearch
-- Description:
--   Generic pipelined binary search module with embedded ROM access.
--   Searches to find index i where: rom(i) <= key < rom(i+1)
--   
-- Generic Parameters:
--   ROM_TYPE: Type definition for the ROM array
--   ROM_DATA: Actual ROM content (constant array)
--   
-- Algorithm:
--   Pipelined binary search with log2(ROM_SIZE) stages.
--   Each stage checks if we can advance by step_size = 2^(N-1-stage).
--   
-- Latency: log2_ceil(ROM_SIZE) + 1 cycles
--   - Stage 0: Input register
--   - Stages 1..N: Binary search steps  
--   - Stage N+1: Output
----------------------------------------------------------------------------------
entity binarysearch is
    generic (
        ROM_SIZE : integer := 64  -- Size of ROM to search
    );
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;
        
        -- Search Interface
        key_in    : in  unsigned(length-1 downto 0);  -- Value to search for
        valid_in  : in  std_logic;
        
        -- ROM Access Interface
        -- The user provides ROM data via these ports
        rom_addr  : out integer range 0 to ROM_SIZE-1;  -- ROM address to read
        rom_data  : in  unsigned(length-1 downto 0);    -- ROM data at address
        
        -- Result
        result_index : out integer range 0 to ROM_SIZE-1;  -- Found index i: ROM(i) <= key
        valid_out    : out std_logic
    );
end entity binarysearch;

architecture rtl of binarysearch is
    
    constant STAGES : integer := log2_ceil(ROM_SIZE);
    
    -- Pipeline stage record
    type stage_t is record
        valid  : std_logic;
        key    : unsigned(length-1 downto 0);
        idx    : integer range 0 to ROM_SIZE-1;
    end record;
    
    type pipe_array_t is array (0 to STAGES) of stage_t;
    signal pipe : pipe_array_t;
    
    -- ROM data captured at each stage
    type rom_data_array_t is array (0 to STAGES-1) of unsigned(length-1 downto 0);
    signal rom_data_reg : rom_data_array_t;
    
    -- Check indices for each stage (combinatorial)
    type check_idx_array_t is array (0 to STAGES-1) of integer range 0 to ROM_SIZE-1;
    signal check_idx_array : check_idx_array_t;

begin

    -- =========================================================================
    -- Stage 0: Input Register
    -- =========================================================================
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                pipe(0).valid <= '0';
                pipe(0).key   <= (others => '0');
                pipe(0).idx   <= 0;
            else
                pipe(0).valid <= valid_in;
                pipe(0).key   <= key_in;
                pipe(0).idx   <= 0;  -- Start search at index 0
            end if;
        end if;
    end process;

    -- =========================================================================
    -- Stages 1..N: Binary Search Steps
    -- =========================================================================
    GEN_SEARCH_STAGES: for i in 0 to STAGES-1 generate
        constant step_size : integer := 2**(STAGES - 1 - i);
        
        signal check_idx : integer range 0 to ROM_SIZE-1;
    begin
        -- Combinatorial: Compute check index for this stage
        process(pipe(i).idx)
            variable v_check_idx : integer;
        begin
            v_check_idx := pipe(i).idx + step_size;
            
            -- Boundary check
            if v_check_idx >= ROM_SIZE then
                v_check_idx := ROM_SIZE - 1;
            end if;
            
            check_idx <= v_check_idx;
            check_idx_array(i) <= v_check_idx;
        end process;
        
        -- Sequential: Capture ROM data and make decision
        process(clk)
        begin
            if rising_edge(clk) then
                if rst = '1' then
                    pipe(i+1).valid <= '0';
                    pipe(i+1).key   <= (others => '0');
                    pipe(i+1).idx   <= 0;
                    rom_data_reg(i) <= (others => '0');
                else
                    -- Propagate valid and key
                    pipe(i+1).valid <= pipe(i).valid;
                    pipe(i+1).key   <= pipe(i).key;
                    
                    -- Capture ROM data (provided by user)
                    rom_data_reg(i) <= rom_data;
                    
                    if pipe(i).valid = '1' then
                        -- Compare key with ROM data
                        -- Decision: if key >= ROM(check_idx), advance lower bound
                        if pipe(i).key >= rom_data_reg(i) then
                            pipe(i+1).idx <= check_idx;
                        else
                            pipe(i+1).idx <= pipe(i).idx;
                        end if;
                    else
                        pipe(i+1).idx <= 0;
                    end if;
                end if;
            end if;
        end process;
    end generate GEN_SEARCH_STAGES;

    -- =========================================================================
    -- ROM Address Output (always use stage 0 check index for ROM lookup)
    -- =========================================================================
    -- Stage 0 performs the first check, all subsequent stages use delayed data
    rom_addr <= check_idx_array(0);

    -- =========================================================================
    -- Output
    -- =========================================================================
    valid_out    <= pipe(STAGES).valid;
    result_index <= pipe(STAGES).idx;

end architecture rtl;
