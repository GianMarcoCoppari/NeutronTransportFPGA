
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
    constant m_negiter : integer := 5; 
	constant m_nreps   : integer := 3;
	constant m_maxiterh : integer := m_blocksize * m_fblocks + m_nreps + (m_negiter + 1); 
	
    
    constant m_kinv    : signed(63 downto 0)  := X"07C4BDB7C0EE8080"; 
    constant m_ln2     : signed(63 downto 0)  := X"0000B17217F7D1CF"; 

	
	type pair_t is record 
		index : integer; 
		value : signed(63 downto 0); 
	end record pair_t; 

	type atanhlut_t is array (0 to m_maxiterh - 1) of pair_t; 
    constant atanhlut : atanhlut_t := (
        (-5, x"0002C5481FB47C79"), 
        (-4, x"00026C0E528C05C8"), 
        (-3, x"000212523D1C6303"), 
        (-2, x"0001B78CE48912B5"), 
        (-1, x"00015AA16394D481"), 
        (0,  x"0000F913957192D2"), 
        (1,  x"00008C9F53D56818"), 
        (2,  x"00004162BBEA0451"), 
        (3,  x"0000202B12393D5D"), 
        (4,  x"00001005588AD375"), 
        (4,  x"00001005588AD375"),
        (5,  x"00000800AAC448D7"),
        (6,  x"000004001556222B"),
        (7,  x"0000020002AAB111"),
        (8,  x"0000010000555588"),
        (9,  x"00000080000AAAAC"),
        (10, x"0000004000015555"), 
        (11, x"0000002000002AAA"),
        (12, x"0000001000000555"),
        (13, x"00000008000000AA"),
        (13, x"00000008000000AA"),
        (14, x"0000000400000015"),
        (15, x"0000000200000002"),
        (16, x"0000000100000000"),
        (17, x"0000000080000000"),
        (18, x"0000000040000000"),
        (19, x"0000000020000000"),
        (20, x"0000000010000000"), 
        (21, x"0000000008000000"),
        (22, x"0000000004000000"),
        (23, x"0000000002000000"),
        (24, x"0000000001000000"),
        (25, x"0000000000800000"),
        (26, x"0000000000400000"),
        (27, x"0000000000200000"),
        (28, x"0000000000100000"),
        (29, x"0000000000080000"),
        (30, x"0000000000040000"),
        (31, x"0000000000020000"),
        (32, x"0000000000010000"),
        (33, x"0000000000008000"),
        (34, x"0000000000004000"),
        (35, x"0000000000002000"),
        (36, x"0000000000001000"), 
        (37, x"0000000000000800"),
        (38, x"0000000000000400"),
        (39, x"0000000000000200"),
        (40, x"0000000000000100"),
        (40, x"0000000000000100"),
        (41, x"0000000000000080"),
        (42, x"0000000000000040"),
        (43, x"0000000000000020"),
        (44, x"0000000000000010"),
        (45, x"0000000000000008"),
        (46, x"0000000000000004"),
        (47, x"0000000000000002"),
        (48, x"0000000000000001")
	);

end package configcordich;

--! @brief Corpo vuoto del package configcordich.
package body configcordich is 
end package body configcordich;