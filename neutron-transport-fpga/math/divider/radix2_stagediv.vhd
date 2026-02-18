library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.config.all;


----------------------------------------------------------------------------------
-- Entity: radix2_stagediv
-- Description:
--   Single stage of a Radix-2 Pipelined Divider.
--   Performs the classic shift-and-subtract step:
--     1. Shift remainder and bring down next dividend bit.
--     2. Compare/Subtract Divisor.
--     3. Determine Quotient bit (1 if subtract valid, 0 otherwise).
--
-- Note: 'length' constant comes from work.config.
----------------------------------------------------------------------------------
entity radix2_stagediv is
    port (
        clk      : in  std_logic;
        rst      : in  std_logic;
        
        -- Dati in ingresso dalla riga precedente
        rem_in   : in  unsigned(length - 1 downto 0); -- Partial Remainder
        divd_in  : in  unsigned(length - 1 downto 0); -- Remaining Dividend
        quot_in  : in  unsigned(length - 1 downto 0); -- Partial Quotient
        divs_in  : in  unsigned(length - 1 downto 0); -- Divisor (propagated)
        
        -- Dati in uscita alla riga successiva
        rem_out  : out unsigned(length - 1 downto 0);
        divd_out : out unsigned(length - 1 downto 0);
        quot_out : out unsigned(length - 1 downto 0);
        divs_out : out unsigned(length - 1 downto 0)
    );
end entity radix2_stagediv;

architecture rtl of radix2_stagediv is
begin
    process(clk)
        -- Variabile per il tentativo di sottrazione (N - D)
        variable v_rem_shifted : unsigned(length - 1 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                rem_out  <= (others => '0');
                divd_out <= (others => '0');
                quot_out <= (others => '0');
                divs_out <= (others => '0');
            else
                -- 1. Propaga Divisore (Costante lungo la colonna)
                divs_out <= divs_in;
                
                -- 2. Shift Dividendo (Prepara bit successivo)
                divd_out <= divd_in(length - 2 downto 0) & '0';

                -- 3. Costruisci il "Numeratore Corrente": Resto << 1 | MSB Dividendo
                v_rem_shifted := rem_in(length - 2 downto 0) & divd_in(length - 1);

                -- 4. CONFRONTO E SOTTRAZIONE
                if v_rem_shifted >= divs_in then
                    rem_out  <= v_rem_shifted - divs_in; -- Sottrai
                    quot_out <= quot_in(length - 2 downto 0) & '1'; -- Shift + 1
                else
                    rem_out  <= v_rem_shifted; -- Mantieni
                    quot_out <= quot_in(length - 2 downto 0) & '0'; -- Shift + 0
                end if;
            end if;
        end if;
    end process;
end architecture rtl;