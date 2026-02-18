LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;


ENTITY CLA IS 
    PORT (
        CLK  : IN STD_LOGIC;
        RST  : IN STD_LOGIC;
        
        A    : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
        B    : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
        CIN  : IN STD_LOGIC;
        
        SUM  : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
        COUT : OUT STD_LOGIC;
        OVF  : OUT STD_LOGIC
    );
END ENTITY CLA;


ARCHITECTURE RTL OF CLA IS 
    SIGNAL C : STD_LOGIC_VECTOR(4 DOWNTO 0); -- COMBINATORIAL
    
    SIGNAL P : STD_LOGIC_VECTOR(3 DOWNTO 0); -- COMBINATORIAL
    SIGNAL G : STD_LOGIC_VECTOR(3 DOWNTO 0); -- COMBINATORIAL
    
    -- REGISTRI PER RITARDARE LE OPERAZIONI DI UN COLPO DI CLOCK
    SIGNAL PREG   : STD_LOGIC_VECTOR(3 DOWNTO 0);
    SIGNAL CINREG : STD_LOGIC;
    
BEGIN 
    COMPUTEPG : PROCESS (CLK, RST) BEGIN 
        IF RST = '1' THEN 
            P      <= (OTHERS => '0');
            G      <= (OTHERS => '0');
            CINREG <= '0';
            
        ELSE 
            IF RISING_EDGE(CLK) THEN 
                P      <= A XOR B;
                G      <= A AND B;
                CINREG <= CIN;
                
            END IF; -- RISING EDGE
        END IF; -- RST
    END PROCESS COMPUTEPG;

    COMPUTECARRY: PROCESS (CLK, RST) BEGIN 
        IF RST = '1' THEN 
            C    <= (OTHERS => '0');
            PREG <= (OTHERS => '0');
            
        ELSE 
            IF RISING_EDGE(CLK) THEN 
                -- CALCOLO DEI RIPORTI IN PARALLELO
                C(0) <= CINREG;
                C(1) <= G(0) OR (P(0) AND CINREG);
                C(2) <= G(1) OR (P(1) AND G(0)) OR (P(1) AND P(0) AND CINREG);
                C(3) <= G(2) OR (P(2) AND G(1)) OR (P(2) AND P(1) AND G(0)) OR (P(2) AND P(1) AND P(0) AND CINREG);
                C(4) <= G(3) OR (P(3) AND G(2)) OR (P(3) AND P(2) AND G(1)) OR (P(3) AND P(2) AND P(1) AND G(0)) OR (P(3) AND P(2) AND P(1) AND P(0) AND CINREG);
                
                -- RITARDO IL SEGNALE P DI UN COLPO DI CLOCK
                PREG <= P;
                
            END IF; -- RISING EDGE 
        END IF; -- RST
    END PROCESS COMPUTECARRY;
    
    REGOUT : PROCESS (CLK, RST) BEGIN 
        IF RST = '1' THEN 
            SUM  <= (OTHERS => '0');
            COUT <= '0';
            OVF  <= '0';
            
        ELSE 
            IF RISING_EDGE(CLK) THEN 
                SUM  <= PREG XOR C(3 DOWNTO 0);
                COUT <= C(4);
                OVF  <= C(4) XOR C(3);
                
            END IF;
        END IF;
    END PROCESS REGOUT;


END ARCHITECTURE RTL;