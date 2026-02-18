--! @file configcordicc.vhd
--! @brief Package di costanti e tabelle per la pipeline CORDIC circolare (trigonometrica).
--! @author Gian Marco Coppari
--! @date 2026/02/10


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.config.all;
use work.configcordic.all;


--! @package configcordicc
--! Costanti e tabelle per la pipeline CORDIC circolare (Q16.48, seno/coseno).
package configcordicc is
    --! @const m_maxiterc
    --! Numero massimo di iterazioni per la pipeline CORDIC circolare (Q16.48).
    constant m_maxiterc : integer := m_blocksize * m_fblocks;

    --! @const m_pi
    --! Costante pi greco in Q16.48 (2^48 * pi).
    constant m_pi : signed(m_blocksize * m_blocks - 1 downto 0) := X"00003243F6A8885A";
	
    --! @const m_pi_2
    --! Costante pi/2 in Q16.48 (2^48 * pi/2).
    constant m_pi_2 : signed(m_blocksize * m_blocks - 1 downto 0) := X"00001921FB54442D";
	
    --! @const m_3pi_2
    --! Costante 3pi/2 in Q16.48 (2^48 * 3pi/2).
    constant m_3pi_2 : signed(m_blocksize * m_blocks - 1 downto 0) := X"00004B65F29CCD07";

    --! @const m_2pi
    --! Costante 2pi in Q16.48 (2^48 * 2pi).
    constant m_2pi : signed(m_blocksize * m_blocks - 1 downto 0) := X"00006487ED5118A0";

    --! @typedef atanlut_t
    --! Tipo array per la tavola delle costanti arctan(2^(-i)) in Q16.48.
    type atanlut_t is array(0 to m_maxiterc - 1) of signed(m_blocksize * m_blocks - 1 downto 0);

    --! @const CORDIC_ATAN_TABLE
    --! Tavola delle costanti arctan(2^-i) * 2^48 (Q16.48) per la pipeline CORDIC circolare.
    constant atanlut : atanlut_t := (
        X"0000C90FDAA22169", X"000076B19C1586ED", X"00003EB6EBF25902", X"00001FD5BA9AAC2F",
        X"00000FFAADDB967F", X"000007FF556EEA5E", X"000003FFEAAB776E", X"000001FFFD555BBC",
        X"000000FFFFAAAADE", X"0000007FFFF55557", X"0000003FFFFEAAAB", X"0000001FFFFFD555",
        X"0000000FFFFFFAAB", X"00000007FFFFFF55", X"00000003FFFFFFEB", X"00000001FFFFFFFD",
        X"0000000100000000", X"0000000080000000", X"0000000040000000", X"0000000020000000",
        X"0000000010000000", X"0000000008000000", X"0000000004000000", X"0000000002000000",
        X"0000000001000000", X"0000000000800000", X"0000000000400000", X"0000000000200000",
        X"0000000000100000", X"0000000000080000", X"0000000000040000", X"0000000000020000",
        X"0000000000010000", X"0000000000008000", X"0000000000004000", X"0000000000002000",
        X"0000000000001000", X"0000000000000800", X"0000000000000400", X"0000000000000200",
        X"0000000000000100", X"0000000000000080", X"0000000000000040", X"0000000000000020",
        X"0000000000000010", X"0000000000000008", X"0000000000000004", X"0000000000000002"
    );

    --! @const kcinv
    --! costante inversa di guadagno dell'algoritmo cordic
    constant kcinv : signed(m_blocksize * m_blocks - 1 downto 0) := X"0001A592148CFB85"; -- da correggere
end package configcordicc;
