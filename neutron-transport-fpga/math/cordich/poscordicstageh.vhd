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
        phi     :  in  signed(63 downto 0);
        
        stateout : out cordicstate_t
    );
end entity poscordicstageh;


architecture rtl of poscordicstageh is
begin
    compute : process (clk, rst) begin 
        if rst = '1' then 
            stateout <= (
                (others => '0'), 
                (others => '0'), 
                (others => '0')
            );
            
        elsif rising_edge(clk) then 
            case mode is 
                when m_rotating =>  -- ROTATING MODE: reduce z to zero
                    if statein.z(statein.z'high) = '0' then 
                        -- angolo residuo positivo, 
                        -- ruotare in senso antiorario, eta = +1
                        -- sottraggo angolo 

                        stateout <= (
                            statein.x + shift_right(statein.y, iter),
                            statein.y + shift_right(statein.x, iter),
                            statein.z - phi
                        );
                    else 
                        -- angolo residuo negativo,
                        -- ruotare in senso orario, eta = -1
                        -- aggiungo angolo

                        stateout <= (
                            statein.x - shift_right(statein.y, iter),
                            statein.y - shift_right(statein.x, iter),
                            statein.z + phi
                        );
                    end if;
                when m_vectoring => -- VECTORING MODE: reduce y to zero
                    if statein.y(statein.y'high) = '0' then 
                        -- componente y positiva, 
                        -- ruotare in senso orario, eta = -1
                        -- sottraggo angolo
                        stateout <= (
                            statein.x - shift_right(statein.y, iter),
                            statein.y - shift_right(statein.x, iter),
                            statein.z - phi
                        );
                    else 
                        -- componente y negativa, 
                        -- ruotare in senso antiorario, eta = +1
                        -- aggiungo angolo
                        stateout <= (
                            statein.x + shift_right(statein.y, iter),
                            statein.y + shift_right(statein.x, iter),
                            statein.z + phi
                        );
                    end if;
            end case; -- mode
        end if; -- rising edge
    end process compute;

end architecture rtl;
