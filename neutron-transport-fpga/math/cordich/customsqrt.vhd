library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.config.all;
use work.configcordic.all;
use work.configcordich.all;


entity customsqrt is
    port (
        clk  : in  std_logic;
        rst  : in  std_logic;
        
        x_in  : in  signed(63 downto 0);
        sqrt_out : out signed(63 downto 0) 
    );
end entity customsqrt;


architecture rtl of customsqrt is 
    signal inputvec  : cordicstate_t; 
    signal outputvec : cordicstate_t; 
    
    constant quarter : signed(63 downto 0) := x"0000400000000000";
begin 
    scale : process (clk, rst)
        variable tempx : signed(127 downto 0);
        variable tempy : signed(127 downto 0);
        
    begin 
        if rst = '1' then 
            inputvec <= (
                (others => '0'), 
                (others => '0'), 
                (others => '0')
            );
        elsif rising_edge(clk) then
            tempx := m_kinv * (x_in + quarter);
            tempy := m_kinv * (x_in - quarter);
            
            inputvec <= (
                tempx(111 downto 48), 
                tempy(111 downto 48), 
                (others => '0'));
        end if;
    end process scale;
    
    instcordich : entity work.cordich(rtl) 
        generic map (
            mode => m_vectoring  
        ) 
        port map (
            clk => clk, 
            rst => rst, 
            
            statein  => inputvec, 
            stateout => outputvec 
        ); 
    
    sqrt_out <= outputvec.x;
end architecture rtl;