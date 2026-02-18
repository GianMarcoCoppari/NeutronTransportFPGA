LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;
USE work.config.ALL;
USE work.configopenmc.ALL;


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
    -- Costanti Mockup
    constant SIGMA_T_FUEL : unsigned(length-1 downto 0) := to_unsigned(10, length);
    
    -- Segnali Interni
    signal w_neg_log_res : unsigned(length-1 downto 0);
    signal w_sigma       : unsigned(length-1 downto 0);
    signal w_quotient    : unsigned(length-1 downto 0);
    signal w_ln_out_signed : signed(length-1 downto 0);

BEGIN
    -- MUX Materiale (Preparation per Memory Read)
    process(material)
    begin
        if material = FUEL then
            w_sigma <= SIGMA_T_FUEL;
        else
            w_sigma <= (others => '0');
        end if;
    end process;

    -- =============================================================
    -- 1. LOGARITMO: -ln(rng)
    -- =============================================================
    Inst_Cordic: entity work.customln
    PORT MAP (
        clk   => clk, 
        rst   => rst,
        win   => signed(resize(rng_val, length)), 
        lnout => w_ln_out_signed
    );

    w_neg_log_res <= unsigned(-w_ln_out_signed);

    -- =============================================================
    -- 2. DIVISIONE: -ln(rng) / Sigma
    -- =============================================================
    instdiv : entity work.divr2
        port map (
            clk => clk,
            rst => rst,

            dividend  => w_neg_log_res,
            divisor   => w_sigma,
            quotient  => w_quotient
        );

    -- Output logic
    process(material, w_quotient)
    begin
        if material = VOID then
            dist_coll <= (others => '1'); -- Infinito
        else
            dist_coll <= w_quotient;
        end if;
    end process;

END Structural;

