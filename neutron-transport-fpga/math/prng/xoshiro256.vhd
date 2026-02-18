-- XOSHIRO256 PRNG VHDL Module


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.config.all;


entity xoshiro256 is
    port (
        clk  : in  std_logic;
        rst  : in  std_logic;
        
        rnd  : out unsigned(63 downto 0)
    );
end entity xoshiro256;


architecture behavioral of xoshiro256 is 
    type state_t is array (0 to 3) of unsigned(63 downto 0);
    signal state : state_t;

    -- segnali intermedi
    signal s2xors0 : unsigned(63 downto 0);
    signal s3xors1 : unsigned(63 downto 0);
    signal t       : unsigned(63 downto 0);

    signal temp : unsigned(63 downto 0);

    function rotl(x : unsigned; k : integer) return unsigned is 
    begin 
        return shift_left(x, k) or shift_right(x, 64 - k);
    end function rotl;


begin 
    -- cablaggio combinatorio
    s2xors0 <= state(1) xor state(0);
    s3xors1 <= state(2) xor state(1);
    t       <= shift_left(state(1), 17); -- shift sinistro di 17 bit

    compute : process (clk, rst) begin 
        if rst = '1' then 
            -- reset non nullo, altrimenti il generatore lineare sottostante fallisce...
            state(0) <= x"1F0D_C637_4613_850F";
            state(1) <= X"D34D_B33F_1029_AE21";
            state(2) <= x"7937_B20A_441F_9932";
            state(3) <= x"9961_2233_AA55_CC77";

            temp <= (others => '0');
            rnd  <= (others => '0');

        else 
            if rising_edge(clk) then 
                -- stage 1 : aggiornamento stato interno
                state(0) <= state(0) xor s3xors1;
                state(1) <= state(1) xor s2xors0;
                state(2) <= s2xors0 xor t;
                state(3) <= rotl(s3xors1, 45);

                -- stage 2 : output
                temp <= rotl(resize(state(1) * 5, 64), 7);

                rnd <= resize(temp * 9, 64);
            end if;
        end if;
    end process compute;
end architecture behavioral;