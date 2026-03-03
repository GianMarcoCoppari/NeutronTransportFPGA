library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.config.all;
use work.configcordic.all;


entity customln is
    port (
        clk   : in  std_logic;
        rst   : in  std_logic;

        win   : in  signed(63 downto 0); -- Input value (Fixed Point)
        lnout : out signed(63 downto 0)  -- Result (Fixed Point)
    );
end entity customln;


architecture rtl of customln is 
    signal x, y : signed(63 downto 0);
    signal statein, stateout : cordicstate_t;
    constant one : signed(63 downto 0) := X"0001000000000000"; -- 1.0 in Q16.48


begin 
    statein <= (
        win + one,  -- x = w + 1
        one - win,  -- y = 1 - w (to ensure y/x = (w-1)/(w+1))
        (others => '0') -- z = 0, we want to compute atanh(y/x) which will be stored in z_out
    );

    instcordich : entity work.cordich(rtl) 
        generic map ( mode => m_vectoring )
        port map (
            clk => clk, 
            rst => rst, 

            statein  => statein,
            stateout => stateout
        );
    
    -- CORDIC vectoring computes atanh((1-w)/(w+1)) which equals -0.5*ln(w).
    -- Multiply by 2: result = -ln(w), which is positive for w in (0,1).
    -- Negate to get -ln(w) with correct sign after vectoring mode fix.
    lnout <= -shift_left(stateout.z, 1);
end architecture rtl;