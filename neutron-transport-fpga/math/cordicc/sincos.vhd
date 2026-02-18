
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.config.all;
use work.configcordic.all;
use work.configcordicc.all;


-- latenza massima: m_maxiterc + 1 cicli (m_maxiterc per le iterazioni + 1 per la riduzione angolo)
entity sincos is
	port (
		clk   : in  std_logic;
		rst   : in  std_logic;

		alpha : in  signed(m_blocksize * m_blocks - 1 downto 0); -- angolo input Q16.48
		s     : out signed(m_blocksize * m_blocks - 1 downto 0); -- sin output Q16.48
		c     : out signed(m_blocksize * m_blocks - 1 downto 0)  -- cos output Q16.48
	);
end entity sincos;


architecture rtl of sincos is
    signal alphar    : signed(m_blocksize * m_blocks - 1 downto 0);
    signal flip      : std_logic;
    signal stateout  : cordicstate_t;
    signal statein_sig : cordicstate_t; -- Intermediate signal for state input

begin
	-- Riduzione angolo e flip segno coseno
	reduce : entity work.reduceangle(rtl)
		port map (
			clk    => clk,
			rst    => rst,

			alpha  => alpha,
			alphar => alphar,
			flip   => flip
		);

	-- Build state input signal
	statein_sig <= (kcinv, (others => '0'), alphar);

	-- CORDIC trigonometrico
	cordicc : entity work.cordicc(rtl)
		port map (
			clk   => clk,
			rst   => rst,

			statein => statein_sig, -- x = 1/K, y = 0, z = alphar
	           stateout => stateout
		);

	-- Output: applica flip segno coseno
	s <= stateout.y;
    c <= stateout.x when flip = '0' else -stateout.x;

end architecture rtl;

