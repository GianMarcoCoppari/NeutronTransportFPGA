library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.configopenmc.all;

entity materiallookup is
    port (
        clk      : in  std_logic; -- Optional for ROM/BRAM
        cell_id  : in  std_logic_vector(ncells-1 downto 0);
        material : out material_t
    );
end entity materiallookup;

architecture behavioral of materiallookup is
begin
    process(cell_id)
        variable id_int : integer;
    begin
        -- Simple combinatorial decoding for now
        -- Assumes cell_id is One-Hot or Binary. 
        -- Given "std_logic_vector(ncells-1 downto 0)", let's assume Binary ID 
        -- or simple mapping.
        
        -- Logic:
        -- Cell 1 (Inner) -> FUEL
        -- Cell 0 (Outer) -> VOID
        -- Others -> VOID
        
        -- Safe Conversion
        id_int := to_integer(unsigned(cell_id));
        
        case id_int is
            when 1 => 
                material <= FUEL;
            when others =>
                material <= VOID;
        end case;
    end process;
end architecture behavioral;
