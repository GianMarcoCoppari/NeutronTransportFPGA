-- Calcola lo step unitario dell'Algoritmo CORDIC Trigonometrico in Modalità Rotazionale
-- per il calcolo delle funzioni sin e cos
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.config.all;
use work.configcordic.all;
use work.configcordicc.all;


entity cordicstagec is 
    generic (
        iter : integer := 0
    );
    port (
        clk      : in  std_logic;
        rst      : in  std_logic;

        statein  : in  cordicstate_t;
        alpha    : in  signed(m_blocksize * m_blocks - 1 downto 0); -- atanlut value
        
        stateout : out cordicstate_t
    );
end entity cordicstagec;


architecture rtl of cordicstagec is 

begin 
    compute : process (clk, rst) begin 
        if rst = '1' then 
            stateout <= ((others => '0'), (others => '0'), (others => '0'));
            
        elsif rising_edge(clk) then 
            -- Modalità rotazione: riduciamo Z a 0
            if statein.z < (statein.z'range => '0') then 
                -- Z è negativo, 
                -- x' = x + (y >> iter)
                -- y' = y - (x >> iter)
                -- z' = z + alpha
                stateout.x <= statein.x + shift_right(statein.y, iter);
                stateout.y <= statein.y - shift_right(statein.x, iter);
                stateout.z <= statein.z + alpha;
            else
                -- Z è positivo,
                -- x' = x - (y >> iter)
                -- y' = y + (x >> iter)
                -- z' = z - alpha 
                stateout.x <= statein.x - shift_right(statein.y, iter);
                stateout.y <= statein.y + shift_right(statein.x, iter);
                stateout.z <= statein.z - alpha;
            end if;
        end if;
    end process compute;
end architecture rtl;