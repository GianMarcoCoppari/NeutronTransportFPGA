library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.config.all;
use work.configcordic.all;
use work.configcordich.all;


entity tb_cordich is
    port (
        xout, yout, zout : out signed(63 downto 0)
    );

end entity tb_cordich;


architecture testbench of tb_cordich is 
    constant period : time := 10 ns;

    signal clk : std_logic := '1';
    signal rst : std_logic := '1';

    signal statein  : cordicstate_t;
    signal stateout : cordicstate_t;


begin 
    dut : entity work.cordich(rtl) port map (
        clk => clk, 
        rst => rst, 

        statein => statein, 
        stateout => stateout
    );

    xout <= stateout.x;
    yout <= stateout.y;
    zout <= stateout.z;


    clock : process begin 
        clk <= '1';
        wait for period / 2;

        clk <= not clk;
        wait for period / 2;
    end process clock;


    stimulus :process begin 
        rst <= '1';
        wait until rising_edge(clk);

        rst <= '0';
        statein <= (x"0001000000000000", (others => '0'), (others => '0'));
        wait until rising_edge(clk);

        for i in 0 to 1000 loop
            wait until rising_edge(clk);
        end loop;
        wait;
    end process stimulus;
end architecture testbench;
