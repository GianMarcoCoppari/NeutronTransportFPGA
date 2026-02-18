library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.config.all;
use work.configopenmc.all; 
use work.configcordic.all; 

----------------------------------------------------------------------------------
-- Entity: negcordicstageh
-- Description:
--   Hyperbolic CORDIC Stage for NEGATIVE iterations (i <= 0).
--   Required for convergence domain of Hyperbolic CORDIC.
--
-- Mathematics:
--   For negative indices, the shift factor is (1 - 2^(i-2)).
--   This translates to: NewVal = Val - (Val >> (2-i)).
--   
--   This stage differs from standard positive stages which use Val >> i.
----------------------------------------------------------------------------------
entity negcordicstageh is
    generic (
        iter : integer := 0; -- Iteration index (e.g., -5, -4...)
        mode : cordicmode_t := m_vectoring
    );
    port (
        clk      : in  std_logic;
        rst      : in  std_logic;

        statein  : in  cordicstate_t;
        phi      : in  signed(m_blocksize * m_blocks - 1 downto 0); -- atanhlut value
        
        stateout : out cordicstate_t
    );
end entity negcordicstageh;

architecture rtl of negcordicstageh is
    -- Internal signals for shifted values calculation
    -- Logic for negative iterations i <= 0:
    -- Factor is (1 - 2^(i-2)). 
    -- Let shift_amt = 2 - iter. (Since iter is negative, shift_amt > 2)
    -- Term = Val * (1 - 2^-k) = Val - (Val >> k)
    
    constant shift_amt : integer := 2 - iter;
    
    signal x_term : signed(statein.x'range);
    signal y_term : signed(statein.y'range);

    signal x_shifted : signed(statein.x'range);
    signal y_shifted : signed(statein.y'range);

begin

    -- Shift logic
    x_shifted <= shift_right(statein.x, shift_amt);
    y_shifted <= shift_right(statein.y, shift_amt);

    -- Calculate the full term to add/sub: (Val - Val >> k)
    -- This implements the multiplication by (1 - 2^(i-2))
    x_term <= statein.x - x_shifted;
    y_term <= statein.y - y_shifted;

    compute : process (clk) 
    begin 
        if rising_edge(clk) then 
            if rst = '1' then 
                stateout.x <= (others => '0');
                stateout.y <= (others => '0');
                stateout.z <= (others => '0');
            else 
                case mode is 
                    when m_rotating => 
                        -- Modalità rotazione: riduciamo Z a 0
                        if statein.z < (statein.z'range => '0') then 
                            -- Z è negativo, dobbiamo ruotare positivamente
                            -- x' = x + y_term
                            -- y' = y + x_term
                            -- z' = z + phi
                            stateout.x <= statein.x + y_term;
                            stateout.y <= statein.y + x_term;
                            stateout.z <= statein.z + phi;
                        else 
                            -- Z è positivo, dobbiamo ruotare negativamente
                            stateout.x <= statein.x - y_term;
                            stateout.y <= statein.y - x_term;
                            stateout.z <= statein.z - phi;
                        end if;

                    when m_vectoring => 
                        -- Modalità vettorizzazione: riduciamo Y a 0
                        if statein.y < (statein.y'range => '0') then 
                            -- Y è negativo, dobbiamo sommare (sigma = -1)
                            stateout.x <= statein.x + y_term;
                            stateout.y <= statein.y + x_term;
                            stateout.z <= statein.z + phi;
                        else 
                            -- Y è positivo, dobbiamo sottrarre (sigma = +1)
                            stateout.x <= statein.x - y_term;
                            stateout.y <= statein.y - x_term;
                            stateout.z <= statein.z - phi;
                        end if;
                end case; 
            end if; -- rst
        end if; -- rising edge
    end process compute;

end architecture rtl;
