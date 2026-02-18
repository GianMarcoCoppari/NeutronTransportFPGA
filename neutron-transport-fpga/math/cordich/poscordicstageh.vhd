library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.config.all;
use work.configcordic.all;


----------------------------------------------------------------------------------
-- Entity: poscordicstageh
-- Description:
--   Hyperbolic CORDIC Stage for POSITIVE iterations (i > 0).
--   Standard CORDIC shift-add/sub architecture.
--
-- Mathematics:
--   Shift factor is 2^(-i).
--   Operations:
--     x' = x +/- (y >> i)
--     y' = y +/- (x >> i)
--     z' = z +/- phi
----------------------------------------------------------------------------------
entity poscordicstageh is
    generic (
        iter : integer := 1;
        mode : cordicmode_t := m_vectoring
    );
    port (
        clk      : in  std_logic;
        rst      : in  std_logic;

        statein  : in  cordicstate_t;
        phi     :  in  signed(m_blocksize * m_blocks - 1 downto 0); -- atanhlut value
        
        stateout : out cordicstate_t
    );
end entity poscordicstageh;


architecture rtl of poscordicstageh is
begin
    compute : process (clk, rst) begin 
        if rst = '1' then 
            stateout <= ((others => '0'), (others => '0'), (others => '0'));
            
        else 
            if rising_edge(clk) then 
                case mode is 
                    when m_rotating => 
                        -- Modalità rotazione: riduciamo Z a 0
                        if statein.z < (statein.z'range => '0') then 
                            -- Z è negativo, dobbiamo ruotare positivamente (sommare angolo)
                            stateout.x <= statein.x + shift_right(statein.y, iter);
                            stateout.y <= statein.y + shift_right(statein.x, iter);
                            stateout.z <= statein.z + phi;
                        else 
                            -- Z è positivo, dobbiamo ruotare negativamente (sottrarre angolo)
                            stateout.x <= statein.x - shift_right(statein.y, iter);
                            stateout.y <= statein.y - shift_right(statein.x, iter);
                            stateout.z <= statein.z - phi;
                        end if;

                    when m_vectoring => 
                        -- Modalità vettorizzazione: riduciamo Y a 0
                        if statein.y < (statein.y'range => '0') then 
                            -- Y è negativo, dobbiamo sommare (sigma = -1)
                            -- x' = x - (-1)y... = x + y...
                            -- z' = z - (-1)phi  = z + phi
                            stateout.x <= statein.x + shift_right(statein.y, iter);
                            stateout.y <= statein.y + shift_right(statein.x, iter);
                            stateout.z <= statein.z + phi;
                        else 
                            -- Y è positivo, dobbiamo sottrarre (sigma = +1)
                            stateout.x <= statein.x - shift_right(statein.y, iter);
                            stateout.y <= statein.y - shift_right(statein.x, iter);
                            stateout.z <= statein.z - phi;
                        end if;
                end case; -- mode
            end if; -- rst
        end if; -- rising edge
    end process compute;

end architecture rtl;
