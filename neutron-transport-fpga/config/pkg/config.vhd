library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


package config is
	constant m_blocksize : integer := 4;
	constant m_blocks    : integer := 16;
	constant m_fblocks   : integer := 12;
    constant length      : integer := m_blocksize * m_blocks;

    constant cla4delay : integer := 3;

    -- Mathematical point type for interpolation (2D point in Q16.48)
    -- Note: unsigned is from ieee.numeric_std (imported above)
    type point_t is record
        x : unsigned(length-1 downto 0);  -- x-coordinate in Q16.48
        y : unsigned(length-1 downto 0);  -- y-coordinate in Q16.48
    end record point_t;

    -- Helper function for calculating log2 (ceiling)
    function log2_ceil(n : integer) return integer;
end package config;


package body config is
    function log2_ceil(n : integer) return integer is
        variable v_log  : integer := 0;
        variable v_temp : integer := n - 1;
    begin
        if n <= 1 then
            return 1; -- Degenerate case, return at least 1 bit/stage
        end if;
        
        while v_temp > 0 loop
            v_log := v_log + 1;
            v_temp := v_temp / 2;
        end loop;
        return v_log;
    end function;
end package body config;
