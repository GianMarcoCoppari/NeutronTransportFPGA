library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.config.all;
use work.configcordic.all;
use work.configcordicc.all;

entity tb_sincos is
end entity tb_sincos;

architecture test of tb_sincos is
    constant period : time := 10 ns;

	signal clk   : std_logic := '1';
	signal rst   : std_logic := '1';
	signal alpha : signed(m_blocksize * m_blocks - 1 downto 0) := (others => '0');
	signal s     : signed(m_blocksize * m_blocks - 1 downto 0);
	signal c     : signed(m_blocksize * m_blocks - 1 downto 0);

	-- Angoli noti (0, pi/4, pi/2, pi, 3pi/2, 2pi)
	type angle_arr is array(0 to 5) of signed(m_blocksize * m_blocks - 1 downto 0);
	constant zero    : signed(m_blocksize * m_blocks - 1 downto 0) := (others => '0');
	constant pi      : signed(m_blocksize * m_blocks - 1 downto 0) := x"0003_243F6A8885A3";
	constant pi_2    : signed(m_blocksize * m_blocks - 1 downto 0) := x"0001_921FB54442D1";
	constant pi_4    : signed(m_blocksize * m_blocks - 1 downto 0) := x"0000_C90FDAA22168";
	constant t3pi_2  : signed(m_blocksize * m_blocks - 1 downto 0) := x"0004_B65F29CCD067";
	constant t2pi    : signed(m_blocksize * m_blocks - 1 downto 0) := x"0006_487ED5110B46";
	constant known_angles : angle_arr := (zero, pi_4, pi_2, pi, t3pi_2, t2pi);

	-- Semplice LFSR per random
	signal lfsr : std_logic_vector(31 downto 0) := x"1A2B3C4D";

begin
	
	dut : entity work.sincos(rtl)
		port map (
			clk   => clk,
			rst   => rst,
			
            alpha => alpha,
			s     => s,
			c     => c
		);


    clock : process begin 
        clk <= '0';
        wait for period / 2;

        clk <= not clk;
        wait for period / 2;
    end process clock;

	stimulus : process begin
        rst <= '1';
        wait until rising_edge(clk);

        rst <= '0';
        wait until rising_edge(clk);


        -- 30°
        alpha <= X"0000860A91C16B9B";
        wait until rising_edge(clk);

        -- 45°
        alpha <= X"0000C90FDAA22169";
        wait until rising_edge(clk);
        
        -- 60°
        alpha <= X"00010C152382D736";
        wait until rising_edge(clk);
        
        -- 90°
        alpha <= X"0001921FB54442D2";
        wait until rising_edge(clk);
        
        -- 120°
        alpha <= X"0002182A4705AE6D";
        wait until rising_edge(clk);
        
        -- 150° 
        alpha <= X"00029E34D8C71A08";
        wait until rising_edge(clk);
        
        -- 180°    
        alpha <= X"0003243F6A8885A3";
        wait until rising_edge(clk);
        wait for 50 * period; -- latency + 2 periodi di margine

        wait; -- fine della simulazione
    end process stimulus;

end architecture test;
