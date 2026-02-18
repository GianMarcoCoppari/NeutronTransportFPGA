library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.config.all;
use work.configcordic.all;

----------------------------------------------------------------------------------
-- Entity: customln
-- Description:
--   Computes the natural logarithm: result = ln(win).
--
-- Algorithm:
--   Hyperbolic CORDIC in Vectoring Mode.
--   Specifically, CORDIC Vectoring calculates: 
--     z_out = z_in + atanh(y_in / x_in)
--   
--   To get ln(w), we use the identity:
--     atanh( (w-1)/(w+1) ) = 0.5 * ln(w)
--     => ln(w) = 2 * atanh( (w-1)/(w+1) )
--
-- Calculate Inputs:
--   We set inputs to CORDIC as:
--   x = w + 1
--   y = w - 1 (actually 1 - w if range constrained, but usually (w-1))
--   Because y/x = (w-1)/(w+1).
--   Note: The implementation below sets X = Win + 1, Y = 1 - Win. 
--   This results in -ln(Win), which is desired for the physics (Exponential Dist).
----------------------------------------------------------------------------------
entity customln is
    port (
        clk   : in  std_logic;
        rst   : in  std_logic;

        win   : in  signed(m_blocksize * m_blocks - 1 downto 0); -- Input value (Fixed Point)
        lnout : out signed(m_blocksize * m_blocks - 1 downto 0)  -- Result (Fixed Point)
    );
end entity customln;


architecture rtl of customln is 
    signal x, y : signed(m_blocksize * m_blocks - 1 downto 0);
    signal stateout : cordicstate_t;

begin 
    compute : process (clk, rst) begin 
        if rst = '1' then 
            x <= (others => '0');
            y <= (others => '0');
        else 
            if rising_edge(clk) then 
                x <= win + signed'(X"0001_000000000000");
                y <= signed'(X"0001_000000000000") - win;

            end if;
        end if;
    end process compute;

    instcordich : entity work.cordich(rtl) 
        generic map ( mode => m_vectoring )
        port map (
            clk => clk, 
            rst => rst, 

            statein  => (x, y, (others => '0')),
            stateout => stateout
        );
    
    lnout <= shift_left(stateout.z, 1); -- ln(x) = 2 * atanh((x-1)/(x+1))
end architecture rtl;