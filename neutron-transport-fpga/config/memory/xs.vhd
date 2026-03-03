library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.config.all;
use work.configopenmc.all;

package xs is
    
    -- =========================================================================
    -- INVERSE TOTAL CROSS SECTIONS (Mean Free Path) - Format Q16.48
    -- Used by advanceworker for distance-to-collision sampling:
    --   dist = -ln(rnd) * (1/Sigma_total)
    -- =========================================================================
    
    -- Fuel: Sigma_total = 50.0 mm^-1 -> 1/50 = 0.02
    -- 0.02 * 2^48 = 5629499534213 
    constant INV_SIGMA_FUEL : unsigned(length-1 downto 0) := x"0000_051E_B851_EB85";
    
    -- U235: Sigma_total = 100.0 mm^-1 -> 1/100 = 0.01
    -- 0.01 * 2^48 = 2814749767106
    constant INV_SIGMA_U235 : unsigned(length-1 downto 0) := x"0000_028F_5C28_F5C2";

    -- Void: Sigma = 0 -> Infinite MFP. 
    -- Represented as max value or handled separately.
    constant INV_SIGMA_VOID : unsigned(length-1 downto 0) := (others => '1');

    -- =========================================================================
    -- INTERACTION PROBABILITY THRESHOLDS (64-bit unsigned, scaled to PRNG range)
    -- Used by eventworker for reaction type sampling.
    -- 
    -- Physics: P_reaction = Sigma_reaction / Sigma_total
    -- Encoding: threshold = P * 2^64 (maps probability [0,1] to [0, 2^64-1])
    --
    -- Usage (cumulative):
    --   if rnd < PROB_ABS        => Absorption
    --   elsif rnd < PROB_ABS + PROB_FISS => Fission
    --   else                      => Scattering
    -- =========================================================================

    -- FUEL material (Sigma_total = 50.0 mm^-1):
    --   Sigma_abs  =  5.0 mm^-1  -> P_abs  = 5.0/50.0  = 0.10
    --   Sigma_fiss =  7.5 mm^-1  -> P_fiss = 7.5/50.0  = 0.15
    --   Sigma_scat = 37.5 mm^-1  -> P_scat = 37.5/50.0 = 0.75
    -- Q16.48: 0.10 * 2^48 = 0x0000_1999..., 0.15 * 2^48 = 0x0000_2666...
    constant PROB_ABS_FUEL  : unsigned(length-1 downto 0) := x"0000_1999_9999_9999"; -- 0.10 Q16.48
    constant PROB_FISS_FUEL : unsigned(length-1 downto 0) := x"0000_2666_6666_6666"; -- 0.15 Q16.48

    -- VOID material: no physical interactions (particle should never collide in void)
    -- Safety fallback: 100% scattering (pass-through)
    constant PROB_ABS_VOID  : unsigned(length-1 downto 0) := (others => '0'); -- 0.0 Q16.48
    constant PROB_FISS_VOID : unsigned(length-1 downto 0) := (others => '0'); -- 0.0 Q16.48

    -- =========================================================================
    -- LOOKUP FUNCTIONS
    -- =========================================================================
    function get_inv_sigma(mat : material_t) return unsigned;
    -- Return interaction probability in Q16.48 format
    function get_prob_abs(mat : material_t)  return unsigned;
    function get_prob_fiss(mat : material_t) return unsigned;

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

    function get_prob_abs(mat : material_t) return unsigned is
    begin
        case mat is
            when FUEL   => return PROB_ABS_FUEL;
            when VOID   => return PROB_ABS_VOID;
            when others => return PROB_ABS_VOID;
        end case;
    end function;

    function get_prob_fiss(mat : material_t) return unsigned is
    begin
        case mat is
            when FUEL   => return PROB_FISS_FUEL;
            when VOID   => return PROB_FISS_VOID;
            when others => return PROB_FISS_VOID;
        end case;
    end function;

end package body xs;
