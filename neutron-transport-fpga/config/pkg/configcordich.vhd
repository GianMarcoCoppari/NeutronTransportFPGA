
--! @file configcordich.vhd
--! @brief Package di costanti e tabelle per la pipeline CORDIC iperbolica (CORDICH).
--! @author Gianmarco
--! @date 2026

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.config.all;
use work.configcordic.all;


package configcordich is 

	--! @const m_negiter
	--! Numero di iterazioni iperboliche "negative" (pre-rotazioni) nella pipeline CORDICH.
	constant m_negiter : integer := 5; 

	--! @const m_nreps
	--! Numero di ripetizioni per la convergenza iperbolica.
	constant m_nreps   : integer := 3;

	--! @const m_maxiterh
	--! Numero massimo di iterazioni della pipeline CORDICH.
	constant m_maxiterh : integer := m_blocksize * m_fblocks + m_nreps + (m_negiter + 1); 

	--! @const m_kinv
	--! Costante di normalizzazione K^-1 per la pipeline CORDICH (Q(m + n, 0) formato).
	constant m_kinv    : signed(m_blocksize * m_blocks - 1 downto 0)  := X"0000_0020F41941AD"; 

	--! @const m_ln2
	--! Costante ln(2) in Q(m + n, 0) formato, utile per funzioni logaritmiche iperboliche.
	constant m_ln2     : signed(m_blocksize * m_blocks - 1 downto 0)  := X"0000_B17217F7D1CF"; 

	--! @struct pair_t
	--! Coppia indice-valore per tabelle costanti o LUT.
	type pair_t is record 
		--! Indice della coppia (ad esempio, iterazione pipeline)
		index : integer; 

		--! Valore associato (Q(m + n, 0) formato, larghezza totale: m_blocksize * m_blocks)
		value : signed(m_blocksize * m_blocks - 1 downto 0); 
	end record pair_t; 

	--! @typedef atanhlut_t
	--! Tipo array per la tabella delle costanti atanh (iperboliche) per la pipeline CORDICH.
	type atanhlut_t is array (0 to m_maxiterh - 1) of pair_t; 

	--! @const atanhlut
	--! Tabella delle costanti atanh (iperboliche) per ogni iterazione della pipeline CORDICH.
	constant atanhlut : atanhlut_t := (
		(-5, X"0002_C5481FB47C79"), 
		(-4, X"0002_6C0E528C05C8"), 
		(-3, X"0002_12523D1C6303"), 
		(-2, X"0001_B78CE48912B5"), 
		(-1, X"0001_5AA16394D481"), 
		(0, X"0000_F913957192D2"), 
		(1, X"0000_8C9F53D56818"), 
		(2, X"0000_4162BBEA0451"), 
		(3, X"0000_202B12393D5D"), 
		(4, X"0000_1005588AD375"), 
		(4, X"0000_1005588AD375"), 
		(5, X"0000_0800AAC448D7"), 
		(6, X"0000_04001556222B"), 
		(7, X"0000_020002AAB111"), 
		(8, X"0000_010000555588"), 
		(9, X"0000_0080000AAAAC"), 
		(10, X"0000_004000015555"), 
		(11, X"0000_002000002AAA"), 
		(12, X"0000_001000000555"), 
		(13, X"0000_0008000000AA"), 
		(13, X"0000_0008000000AA"), 
		(14, X"0000_000400000015"), 
		(15, X"0000_000200000002"), 
		(16, X"0000_000100000000"), 
		(17, X"0000_000080000000"), 
		(18, X"0000_000040000000"), 
		(19, X"0000_000020000000"), 
		(20, X"0000_000010000000"), 
		(21, X"0000_000008000000"), 
		(22, X"0000_000004000000"), 
		(23, X"0000_000002000000"), 
		(24, X"0000_000001000000"), 
		(25, X"0000_000000800000"), 
		(26, X"0000_000000400000"), 
		(27, X"0000_000000200000"), 
		(28, X"0000_000000100000"), 
		(29, X"0000_000000080000"), 
		(30, X"0000_000000040000"), 
		(31, X"0000_000000020000"), 
		(32, X"0000_000000010000"), 
		(33, X"0000_000000008000"), 
		(34, X"0000_000000004000"), 
		(35, X"0000_000000002000"), 
		(36, X"0000_000000001000"), 
		(37, X"0000_000000000800"), 
		(38, X"0000_000000000400"), 
		(39, X"0000_000000000200"), 
		(40, X"0000_000000000100"), 
		(40, X"0000_000000000100"), 
		(41, X"0000_000000000080"), 
		(42, X"0000_000000000040"), 
		(43, X"0000_000000000020"), 
		(44, X"0000_000000000010"), 
		(45, X"0000_000000000008"), 
		(46, X"0000_000000000004"), 
		(47, X"0000_000000000002"), 
		(48, X"0000_000000000001")
	);

end package configcordich;

--! @brief Corpo vuoto del package configcordich.
package body configcordich is 
end package body configcordich;