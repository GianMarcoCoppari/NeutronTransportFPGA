LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;
USE WORK.CONFIG.ALL;


ENTITY TB_CLA IS 
END ENTITY TB_CLA;

ARCHITECTURE BEHAVIORAL OF TB_CLA IS 
    SIGNAL CLK  : STD_LOGIC := '1';
    SIGNAL RST  : STD_LOGIC := '1';
        
    SIGNAL A    : STD_LOGIC_VECTOR(M_BLOCKSIZE - 1 DOWNTO 0) := (OTHERS => '0');
    SIGNAL B    : STD_LOGIC_VECTOR(M_BLOCKSIZE - 1 DOWNTO 0) := (OTHERS => '0');
    SIGNAL CIN  : STD_LOGIC := '0';
        
    SIGNAL SUM  : STD_LOGIC_VECTOR(M_BLOCKSIZE - 1 DOWNTO 0);
    SIGNAL COUT : STD_LOGIC;
    SIGNAL OVF  : STD_LOGIC;
    
BEGIN 
    DUT : ENTITY WORK.CLA4(RTL) 
        PORT MAP (
            CLK  => CLK, 
            RST  => RST, 
            
            A    => A, 
            B    => B, 
            CIN  => CIN, 
            
            SUM  => SUM, 
            COUT => COUT, 
            OVF  => OVF
        );


    CLOCK : PROCESS BEGIN 
        CLK <= '1';
        WAIT FOR PERIOD / 2;
        
        CLK <= NOT CLK;
        WAIT FOR PERIOD / 2;
    END PROCESS CLOCK;
    
    
    STIMULUS : PROCESS BEGIN 
        RST <= '1';
        WAIT UNTIL RISING_EDGE(CLK);
        
        RST <= '0';
        WAIT UNTIL RISING_EDGE(CLK);
        
        A <= X"2";
        B <= X"3";
        CIN <= '0';
        WAIT UNTIL RISING_EDGE(CLK);
        
        
        A <= X"7";
        B <= X"1";
        CIN <= '0';
        WAIT UNTIL RISING_EDGE(CLK);
        
        
        A <= X"F";
        B <= X"0";
        CIN <= '1';
        WAIT UNTIL RISING_EDGE(CLK);
        
        
        A <= X"7";
        B <= X"7";
        CIN <= '0';
        WAIT UNTIL RISING_EDGE(CLK);
        
        
        WAIT;
        
    END PROCESS STIMULUS;
END ARCHITECTURE BEHAVIORAL;