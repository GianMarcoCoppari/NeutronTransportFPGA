-- GIAN MARCO COPPARI
-- UNIVERSITA' DI BOLOGNA -- LM IN PHYSICS
-- 20260120

LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;
USE WORK.CONFIG.ALL;


ENTITY CCLA IS
    GENERIC (
        BLOCKS : INTEGER := M_BLOCKS
    );
    PORT (
        CLK  : IN STD_LOGIC;
        RST  : IN STD_LOGIC;
        
        A    : IN STD_LOGIC_VECTOR(M_BLOCKSIZE * BLOCKS - 1 DOWNTO 0);
        B    : IN STD_LOGIC_VECTOR(M_BLOCKSIZE * BLOCKS - 1 DOWNTO 0);
        CIN  : IN STD_LOGIC;
        
        SUM  : OUT STD_LOGIC_VECTOR(M_BLOCKSIZE * BLOCKS - 1 DOWNTO 0);
        COUT : OUT STD_LOGIC;
        OVF  : OUT STD_LOGIC
    );
END ENTITY CCLA;


ARCHITECTURE PIPE OF CCLA IS 
    TYPE BLOCKDELAY_T IS ARRAY (NATURAL RANGE <>) OF STD_LOGIC_VECTOR(M_BLOCKSIZE - 1 DOWNTO 0);
    
    SIGNAL CTEMP : STD_LOGIC_VECTOR(BLOCKS DOWNTO 0);
    SIGNAL OTEMP : STD_LOGIC_VECTOR(BLOCKS - 1 DOWNTO 0);
    
    
BEGIN 
    -- ASSEGNAZIONE COMBINATORIA DEL PRIMO INPUT CARRY
    CTEMP(0) <= CIN;

    GENBLOCKS : FOR I IN 0 TO BLOCKS - 1 GENERATE 
        -- SEGNALI LOCALI DI BLOCCO, PIAZZATI VICINI IN FASE DI PLACE&ROUTING
        SIGNAL ASLICE, BSLICE : STD_LOGIC_VECTOR(M_BLOCKSIZE - 1 DOWNTO 0);
        SIGNAL ASKEW, BSKEW : BLOCKDELAY_T(0 TO I * 3);
        SIGNAL SSKEW : BLOCKDELAY_T(0 TO (BLOCKS - 1 - I) * 3);
        
        SIGNAL STEMP : STD_LOGIC_VECTOR(M_BLOCKSIZE - 1 DOWNTO 0);
        
        
    BEGIN 
        ASLICE <= A((I + 1) * M_BLOCKSIZE - 1 DOWNTO I * M_BLOCKSIZE);
        BSLICE <= B((I + 1) * M_BLOCKSIZE - 1 DOWNTO I * M_BLOCKSIZE);
        
        
        -- QUESTO PROCESSO RITARDA AUTOMATICAMENTE IL J-ESIMO BLOCCO DA SOMMARE
        COMPUTESKEW : PROCESS (CLK, RST) BEGIN 
            IF RST = '1' THEN 
                ASKEW <= (OTHERS => (OTHERS => '0'));
                BSKEW <= (OTHERS => (OTHERS => '0'));
                
            ELSE 
                IF RISING_EDGE(CLK) THEN 
                    ASKEW(0) <= ASLICE;
                    BSKEW(0) <= BSLICE;
                    
                    IF I > 0 THEN 
                        FOR J IN 0 TO I * 3 - 1 LOOP 
                            ASKEW(J + 1) <= ASKEW(J);
                            BSKEW(J + 1) <= BSKEW(J);
                            
                        END LOOP;
                    END IF;
                END IF; -- RISING EDGE
            END IF; -- RST
        END PROCESS COMPUTESKEW;
        
        INSTCLA : ENTITY WORK.CLA(RTL) 
            PORT MAP (
                CLK  => CLK, 
                RST  => RST, 
                
                A    => ASKEW(I * 3), 
                B    => BSKEW(I * 3), 
                CIN  => CTEMP(I), 
                
                SUM  => STEMP, 
                COUT => CTEMP(I + 1), 
                OVF  => OTEMP(I)
            );
            
            
            PROCESS(CLK, RST) BEGIN
                IF RST = '1' THEN
                    SSKEW <= (OTHERS => (OTHERS => '0'));
                    
                ELSIF RISING_EDGE(CLK) THEN
                    SSKEW(0) <= STEMP;
                    
                    -- Riallineamento temporale delle somme
                    IF (BLOCKS - 1 - I) > 0 THEN
                        FOR J IN 0 TO (BLOCKS - 1 - I) * 3 - 1 LOOP
                            SSKEW(J + 1) <= SSKEW(J);
                        END LOOP;
                    END IF;
                END IF;
            END PROCESS;
            
            
            -- ASSEGNAZIONE COMBINATORIA DEL BLOCCO DI SOMMA
            SUM((I + 1) * M_BLOCKSIZE - 1 DOWNTO I * M_BLOCKSIZE) <= SSKEW((BLOCKS -1 - I) * 3);
    END GENERATE GENBLOCKS;
    
    -- ASSEGNAZIONE COMBINATORIA DEL RIPORTO IN USCITA E DELL'OVERFLOW ARITMETICO
    COUT <= CTEMP(CTEMP'HIGH);
    OVF  <= OTEMP(OTEMP'HIGH);

END ARCHITECTURE PIPE;