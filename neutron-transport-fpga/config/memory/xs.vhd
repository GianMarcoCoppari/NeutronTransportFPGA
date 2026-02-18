library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.config.all;
use work.configopenmc.all;

package xs is
    
    -- Format: Q16.48 
    -- Inverse Cross Sections (Mean Free Path)
    -- 1/Sigma
    
    -- Fuel: Sigma = 50.0 -> 1/50 = 0.02
    -- 0.02 * 2^48 = 5629499534213 
    constant INV_SIGMA_FUEL : unsigned(length-1 downto 0) := x"0000_051E_B851_EB85";
    
    -- U235: Sigma = 100.0 -> 1/100 = 0.01
    -- 0.01 * 2^48 = 2814749767106
    constant INV_SIGMA_U235 : unsigned(length-1 downto 0) := x"0000_028F_5C28_F5C2";

    -- Void: Sigma = 0 -> Infinite MFP. 
    -- Represented as max value or handled separately.
    constant INV_SIGMA_VOID : unsigned(length-1 downto 0) := (others => '1');

    function get_inv_sigma(mat : material_t) return unsigned;

end package xs;

package body xs is

    function get_inv_sigma(mat : material_t) return unsigned is
    begin
        case mat is
            when FUEL => return INV_SIGMA_FUEL;
            when VOID => return INV_SIGMA_VOID;
            when others => return INV_SIGMA_VOID;
        end case;
    end function;

end package body xs;
