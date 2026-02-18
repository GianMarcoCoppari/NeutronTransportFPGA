LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;
USE work.config.ALL;
USE work.configopenmc.ALL;

----------------------------------------------------------------------------------
-- Entity: divr2
-- Description:
--   Radix-2 Non-Restoring Pipelined Divider.
--   Computes Quotient = Dividend / Divisor.
--
-- Performance:
--   Latency: 'length' cycles (e.g., 64 cycles for 64-bit).
--   Throughput: 1 result per clock (Pipelined).
--
-- Architecture:
--   Consists of 'length' stages of 'radix2_stagediv'.
--   Each stage resolves 1 bit of the quotient.
--   Uses arrays to interconnect stages for fully unrolled pipeline generation.
----------------------------------------------------------------------------------
ENTITY divr2 IS
    PORT (
        clk      : IN  std_logic;
        rst      : IN  std_logic;
        dividend : IN  unsigned(length-1 downto 0); -- Numerator
        divisor  : IN  unsigned(length-1 downto 0); -- Denominator
        quotient : OUT unsigned(length-1 downto 0)  -- Result
    );
END divr2;

ARCHITECTURE Behavioral OF divr2 IS
    
    -- Array per interconnettere gli stadi della pipeline
    -- length stadi div r2 => length+1 bus (0..length)
    type bus_array is array (0 to length) of unsigned(length-1 downto 0);
    
    signal pipe_rem  : bus_array;
    signal pipe_divd : bus_array;
    signal pipe_quot : bus_array;
    signal pipe_divs : bus_array;

BEGIN

    -- Inizializzazione Pipeline (Stadio 0)
    pipe_rem(0)  <= (others => '0');
    pipe_divd(0) <= dividend; 
    pipe_quot(0) <= (others => '0');
    pipe_divs(0) <= divisor;

    -- Generazione Stadi Radix-2
    gen_div: for i in 0 to length-1 generate
        inst_stage : entity work.radix2_stagediv(rtl)
            port map (
                clk      => clk,
                rst      => rst,
                
                rem_in   => pipe_rem(i),
                divd_in  => pipe_divd(i),
                quot_in  => pipe_quot(i),
                divs_in  => pipe_divs(i),
                
                rem_out  => pipe_rem(i+1),
                divd_out => pipe_divd(i+1),
                quot_out => pipe_quot(i+1),
                divs_out => pipe_divs(i+1)
            );
    end generate gen_div;

    -- Output Finale
    quotient <= pipe_quot(length); 

END Behavioral;