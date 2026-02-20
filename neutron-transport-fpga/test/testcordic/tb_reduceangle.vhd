library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.config.all;
use work.configcordic.all;
use work.configcordicc.all;


entity tb_reduceangle is
end tb_reduceangle;


architecture rtl of tb_reduceangle is
    constant period : time := 10 ns;

    signal clk    : std_logic := '1';
    signal rst    : std_logic := '1';
    signal alpha  : signed(m_blocksize * m_blocks - 1 downto 0) := (others => '0');
    signal alphar : signed(m_blocksize * m_blocks - 1 downto 0);
    signal flip   : std_logic;

begin 
    dut : entity work.reduceangle(rtl) 
        port map (
            clk    => clk,
            rst    => rst,

            alpha  => alpha,
            alphar => alphar,
            flip   => flip
        );

        
    clock : process begin 
        clk <= '1';
        wait for period / 2;

        clk <= not clk;
        wait for period / 2;
    end process clock;


    stimulus : process begin 
        rst <= '1';
        wait until rising_edge(clk);

        rst <= '0';
        wait until rising_edge(clk);



        -- Test cases: {input, expected alphar, expected flip}
        type test_t is record
            input : signed(m_blocksize * m_blocks - 1 downto 0);
            expected_alphar : signed(m_blocksize * m_blocks - 1 downto 0);
            expected_flip   : std_logic;
        end record;
        constant tests : array(0 to 9) of test_t := (
            -- alpha, expected alphar, expected flip
            (X"0000000000000000", X"0000000000000000", '0'), -- 0
            (X"0000860A91C16B9B", X"0000860A91C16B9B", '0'), -- pi/6
            (X"0000C90FDAA22169", X"0000C90FDAA22169", '0'), -- pi/4
            (X"00010C152382D736", X"00010C152382D736", '0'), -- pi/3
            (X"0001921FB54442D2", X"0001921FB54442D2", '0'), -- pi/2
            (X"0002182A4705AE6D", X"00030C1B4B3BDAA7", '1'), -- 2pi/3 -> pi - alpha
            (X"00025B2F8FE6643A", X"0002C8E2D5B22169", '1'), -- 3pi/4 -> pi - alpha
            (X"00029E34D8C71A08", X"0002820B91C16B9B", '1'), -- 5pi/6 -> pi - alpha
            (X"0003243F6A8885A3", X"FFFFFFFFFFFFFFFF", '1'), -- pi (pi - pi = 0)
            (X"0003_243F6A8885A3", X"FFFFFFFFFFFFFFFF", '1')  -- 7pi/6 (pi - alpha < 0)
        );
        for i in 0 to 9 loop
            alpha <= tests(i).input;
            wait until rising_edge(clk);
            report "Test " & integer'image(i) &
                   ": alpha = " & to_hstring(std_logic_vector(alpha)) &
                   ", alphar = " & to_hstring(std_logic_vector(alphar)) &
                   ", flip = " & std_logic'image(flip) &
                   ", expected alphar = " & to_hstring(std_logic_vector(tests(i).expected_alphar)) &
                   ", expected flip = " & std_logic'image(tests(i).expected_flip) &
                   (if (alphar = tests(i).expected_alphar and flip = tests(i).expected_flip) then " [OK]" else " [FAIL]");
        end loop;
        wait;

    end process stimulus;
end architecture rtl;