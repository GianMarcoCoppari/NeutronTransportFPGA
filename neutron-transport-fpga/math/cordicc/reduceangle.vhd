library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.config.all;
use work.configcordic.all;
use work.configcordicc.all;

-- Riduce l'angolo alpha nel range [-pi/2, pi/2] e calcola il flip del coseno
entity reduceangle is
	port (
		clk    : in  std_logic;
		rst    : in  std_logic;
        
		alpha  : in  signed(m_blocksize * m_blocks - 1 downto 0); -- angolo input Q16.48
		alphar : out signed(m_blocksize * m_blocks - 1 downto 0); -- angolo ridotto Q16.48
		flip   : out std_logic            -- flip segno coseno, output flag
	);
end entity reduceangle;


architecture rtl of reduceangle is
begin
	process(clk, rst)
	begin
		if rst = '1' then
			alphar <= (others => '0');
            flip   <= '0';

		elsif rising_edge(clk) then
			if ((alpha > m_pi_2) and (alpha < m_3pi_2)) then
                -- se alpha nel secondo o terzo quadrante, riduci alpha
                -- flip angle
				alphar <= m_pi - alpha;
				flip   <= '1'; -- flip segno coseno
			else 
                -- alpha nel primo o quarto quadrante
                -- no flip
                alphar <= alpha;
                flip   <= '0';
            end if;
		end if;
	end process;
end architecture rtl;
