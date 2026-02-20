library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.configopenmc.all;

----------------------------------------------------------------------------------
-- Testbench: tb_fifo
-- Descrizione: 
--   Verifica il funzionamento base della FIFO sincrona.
--   - Scrittura
--   - Lettura
--   - Full/Empty flags
----------------------------------------------------------------------------------
entity tb_fifo is
end entity tb_fifo;

architecture behavioral of tb_fifo is

    component particle_fifo is
        generic (
            DEPTH_LOG2 : integer := 8 
        );
        port (
            clk     : in  std_logic;
            rst     : in  std_logic;
            din     : in  particle_t;
            wr_en   : in  std_logic;
            full    : out std_logic;
            dout    : out particle_t;
            rd_en   : in  std_logic;
            empty   : out std_logic;
            data_count : out integer
        );
    end component;

    signal clk        : std_logic := '0';
    signal rst        : std_logic := '0';
    
    signal din        : particle_t := EMPTYPARTICLE;
    signal wr_en      : std_logic := '0';
    signal full       : std_logic;
    
    signal dout       : particle_t;
    signal rd_en      : std_logic := '0';
    signal empty      : std_logic;
    signal data_count : integer;

    constant CLK_PERIOD : time := 10 ns;

begin

    uut : particle_fifo
        generic map ( DEPTH_LOG2 => 4 ) -- Piccola FIFO (16 elementi) per testare FULL velocemente
        port map (
            clk => clk, rst => rst,
            din => din, wr_en => wr_en, full => full,
            dout => dout, rd_en => rd_en, empty => empty,
            data_count => data_count
        );

    -- Clock Gen
    clk_process : process
    begin
        clk <= '0'; wait for CLK_PERIOD/2;
        clk <= '1'; wait for CLK_PERIOD/2;
    end process;

    -- Stimulus
    process
    begin
        rst <= '1';
        wait for CLK_PERIOD*5;
        rst <= '0';
        wait for CLK_PERIOD;
        
        report "--- TEST START ---";
        
        -- 1. Scrittura singola
        report "1. Writing 1 particle";
        din.id <= std_logic_vector(to_unsigned(1, 16)); -- 16-bit vector for ID
        wr_en <= '1';
        wait for CLK_PERIOD;
        wr_en <= '0';
        wait for CLK_PERIOD;
        
        assert empty = '0' report "FIFO should not be empty" severity error;
        assert data_count = 1 report "Count should be 1" severity error;
        
        -- 2. Lettura singola
        report "2. Reading 1 particle";
        rd_en <= '1';
        wait for CLK_PERIOD;
        rd_en <= '0';
        
        -- Il dato esce al ciclo successivo al rd_en (sincrono)
        wait for CLK_PERIOD; 
        assert dout.id = std_logic_vector(to_unsigned(1, 16)) report "Data Mismatch" severity error;
        assert empty = '1' report "FIFO should be empty" severity error;
        
        wait for CLK_PERIOD*5;
        
        -- 3. Riempimento (Fill to Full)
        report "3. Filling FIFO (Depth 16)";
        for i in 1 to 16 loop
            din.id <= std_logic_vector(to_unsigned(i, 16));
            wr_en <= '1';
            wait for CLK_PERIOD;
        end loop;
        wr_en <= '0';
        
        wait for CLK_PERIOD;
        assert full = '1' report "FIFO should be FULL" severity error;
        
        -- 4. Lettura Svuotamento
        report "4. Emptying FIFO";
        for i in 1 to 16 loop
            rd_en <= '1';
            wait for CLK_PERIOD;
            -- Check data with 1 cycle lag if strict loop, but simpler just to drain
        end loop;
        rd_en <= '0';
        
        wait for CLK_PERIOD;
        assert empty = '1' report "FIFO should be empty after drain" severity error;

        report "--- TEST COMPLETED ---";
        std.env.stop;
        wait;
    end process;

end architecture behavioral;
