LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;
USE WORK.CONFIG.ALL;


ENTITY TB_CCLA IS
END ENTITY TB_CCLA;

ARCHITECTURE BEHAVIORAL OF TB_CCLA IS
    CONSTANT BLOCKS  : INTEGER := M_BLOCKS;
    CONSTANT LATENCY : INTEGER := M_BLOCKS * M_CLA4LATENCY;
    
    
    SIGNAL CLK  : STD_LOGIC := '0';
    SIGNAL RST  : STD_LOGIC := '0';
    
    SIGNAL A    : STD_LOGIC_VECTOR(M_BLOCKSIZE * M_BLOCKS - 1 DOWNTO 0) := (OTHERS => '0');
    SIGNAL B    : STD_LOGIC_VECTOR(M_BLOCKSIZE * M_BLOCKS - 1 DOWNTO 0) := (OTHERS => '0');
    SIGNAL CIN  : STD_LOGIC := '0';
    
    SIGNAL SUM  : STD_LOGIC_VECTOR(M_BLOCKSIZE * M_BLOCKS - 1 DOWNTO 0);
    SIGNAL COUT : STD_LOGIC;
    SIGNAL OVF  : STD_LOGIC;


BEGIN
    -- Istanza del CCLA (UUT - Unit Under Test)
    uut: ENTITY work.CCLA
        GENERIC MAP ( BLOCKS => BLOCKS )
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


    -- Generatore di Clock
    CLOCK : PROCESS BEGIN
        CLK <= '0'; 
        WAIT FOR PERIOD / 2;
        
        CLK <= '1'; 
        WAIT FOR PERIOD / 2;
    END PROCESS CLOCK;

    -- Processo di stimolo
    STIMULUS : PROCESS BEGIN
        RST <= '1';
        WAIT UNTIL RISING_EDGE(CLK);
        
        RST <= '0';
        WAIT UNTIL RISING_EDGE(CLK);

  
        -- OPERAZIONE: 10 + 20
        A   <= STD_LOGIC_VECTOR(TO_UNSIGNED(10, A'length));
        B   <= STD_LOGIC_VECTOR(TO_UNSIGNED(20, B'length));
        WAIT UNTIL RISING_EDGE(CLK);

        -- OPERAZIONE: 100 + 200
        A <= STD_LOGIC_VECTOR(TO_UNSIGNED(100, A'length));
        B <= STD_LOGIC_VECTOR(TO_UNSIGNED(200, B'length));
        WAIT UNTIL RISING_EDGE(CLK);

        -- OPERAZIONE 3: MAX + 1
        A <= (OTHERS => '1'); -- Tutti 1
        B <= STD_LOGIC_VECTOR(TO_UNSIGNED(1, B'length)); -- +1
        WAIT UNTIL RISING_EDGE(CLK);

        -- 3. Alimentazione costante per riempire la pipeline
        -- Inviamo numeri incrementali per vedere il flusso
        FOR I IN 1 TO 40 LOOP
            A <= STD_LOGIC_VECTOR(TO_UNSIGNED(I, A'length));
            B <= STD_LOGIC_VECTOR(TO_UNSIGNED(I, B'length));
            WAIT UNTIL RISING_EDGE(CLK);
        END LOOP;

        
        -- Attendiamo abbastanza tempo per vedere l'ultimo risultato uscire
        WAIT FOR PERIOD * (LATENCY + 5);
        WAIT;
    END PROCESS STIMULUS;

END ARCHITECTURE BEHAVIORAL;