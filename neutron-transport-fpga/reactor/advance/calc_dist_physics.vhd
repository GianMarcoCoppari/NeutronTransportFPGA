LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;
USE work.config.ALL;
USE work.configopenmc.ALL;
USE work.xs.ALL;


ENTITY CalcDistPhysics IS
    PORT (
        clk        : IN  STD_LOGIC;
        rst        : IN  STD_LOGIC;
        
        material   : IN  material_t;
        rng_val    : IN  unsigned(63 downto 0);
        
        dist_coll  : OUT unsigned(length-1 downto 0)
    );
END CalcDistPhysics;

ARCHITECTURE Structural OF CalcDistPhysics IS
    
    -- Segnali Interni
    signal w_inv_sigma   : unsigned(length-1 downto 0);  -- 1/Sigma_t from xs package (Q16.48)
    signal w_neg_log     : unsigned(length-1 downto 0);  -- -ln(rng) (Q16.48)
    signal w_ln_out_signed : signed(length-1 downto 0);
    signal w_product     : unsigned(2*length-1 downto 0); -- full 128-bit product
    signal w_dist        : unsigned(length-1 downto 0);   -- truncated result (Q16.48)

BEGIN
    -- MUX Materiale: lookup 1/Sigma_t from cross section data
    w_inv_sigma <= get_inv_sigma(material);

    -- =============================================================
    -- 1. LOGARITMO: -ln(rng)
    -- customln computes -ln(win), output is signed Q16.48
    -- =============================================================
    Inst_Cordic: entity work.customln
    PORT MAP (
        clk   => clk, 
        rst   => rst,
        win   => signed(resize(rng_val, length)), 
        lnout => w_ln_out_signed
    );

    -- -ln(rng) is positive (since rng in [0,1]), convert to unsigned
    w_neg_log <= unsigned(w_ln_out_signed);

    -- =============================================================
    -- 2. MOLTIPLICAZIONE: dist = -ln(rng) * (1/Sigma_t)
    -- Both operands in Q16.48, product is Q32.96
    -- Extract Q16.48 result by taking bits [111:48]
    -- =============================================================
    w_product <= w_neg_log * w_inv_sigma;
    w_dist    <= w_product(111 downto 48);  -- Q16.48 slice of Q32.96

    -- Output logic
    process(material, w_dist)
    begin
        if material = VOID then
            dist_coll <= (others => '1'); -- Infinito
        else
            dist_coll <= w_dist;
        end if;
    end process;

END Structural;

