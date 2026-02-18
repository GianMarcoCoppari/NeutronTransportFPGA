library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.configopenmc.all; -- Importiamo particle_t

----------------------------------------------------------------------------------
-- Entity: particle_fifo
-- Description: 
--   Buffer circolare sincrono per memorizzare le particelle in attesa.
--   Supporta scrittura (push) e lettura (pop) simultanee.
----------------------------------------------------------------------------------
entity particle_fifo is
    generic (
        DEPTH_LOG2 : integer := 8 -- Profondità = 2^8 = 256 elementi
    );
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;
        
        -- Write Interface (Input dalla Pipeline o dall'Host)
        din     : in  particle_t;
        wr_en   : in  std_logic;
        full    : out std_logic;
        
        -- Read Interface (Output verso la Pipeline)
        dout    : out particle_t;
        rd_en   : in  std_logic;
        empty   : out std_logic;
        
        -- Status
        data_count : out integer range 0 to 2**DEPTH_LOG2
    );
end entity particle_fifo;

architecture rtl of particle_fifo is
    
    constant DEPTH : integer := 2**DEPTH_LOG2;
    
    -- Memoria FIFO (Array di record particle_t)
    type memory_t is array (0 to DEPTH-1) of particle_t;
    signal mem : memory_t; -- Non inizializzata per sintesi efficiente (BRAM/LUTRAM)
    
    -- Puntatori
    signal head : unsigned(DEPTH_LOG2-1 downto 0) := (others => '0'); -- Write Pointer
    signal tail : unsigned(DEPTH_LOG2-1 downto 0) := (others => '0'); -- Read Pointer
    
    -- Contatore elementi (utile per generare full/empty)
    signal count : integer range 0 to DEPTH := 0;
    
    -- Segnali interni
    signal full_i  : std_logic;
    signal empty_i : std_logic;

begin

    -- Logica combinatoria stato
    full_i  <= '1' when count = DEPTH else '0';
    empty_i <= '1' when count = 0     else '0';
    
    full  <= full_i;
    empty <= empty_i;
    data_count <= count;

    -- Processo sincrono unico
    process(clk, rst) begin
        if rst = '1' then 
            head  <= (others => '0');
            tail  <= (others => '0');
            count <= 0;

            -- Opzionale: pulire dout, ma non strettamente necessario
            dout <= EMPTYPARTICLE; 
        else 
            if rising_edge(clk) then
                -- Scrittura
                if (wr_en = '1' and full_i = '0') then
                    mem(to_integer(head)) <= din;
                    head <= head + 1;
                end if; -- high write enable and non-full fifo
                
                -- Lettura
                -- Nota: Implementazione "First Word Fall through" (FWFT) o standard?
                -- Questa è una standard: il dato è valido al ciclo DOPO rd_en.
                -- Per avere data valid subito (FWFT) servirebbe logica extra.
                -- Qui assumiamo standard read: alzi rd_en, al ciclo dopo hai il dato.
                -- MA ATTENZIONE: Se usiamo 'mem(tail)' direttamente asincrono è FWFT-like.
                -- Facciamo una lettura sincrono standard.
                if (rd_en = '1' and empty_i = '0') then
                    dout <= mem(to_integer(tail));
                    tail <= tail + 1;
                end if; -- read enable and non-empty fifo

                -- Aggiornamento Count
                if (wr_en = '1' and full_i = '0') and (rd_en = '1' and empty_i = '0') then
                    -- Scrittura e Lettura simultanea: count non cambia
                    null;
                elsif (wr_en = '1' and full_i = '0') then
                    count <= count + 1;
                elsif (rd_en = '1' and empty_i = '0') then
                    count <= count - 1;
                end if; -- fifo update

            end if; -- rising edge
        end if; -- rst 
    end process;

end architecture rtl;
