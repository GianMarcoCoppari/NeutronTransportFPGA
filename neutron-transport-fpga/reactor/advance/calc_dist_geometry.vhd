LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;
use work.config.all;
USE work.configopenmc.ALL;


ENTITY CalcDistGeometry IS
    PORT (
        clk        : IN  STD_LOGIC; -- Aggiunto CLK per moduli sincroni
        rst        : IN  STD_LOGIC;
        
        position   : IN  position_t;
        direction  : IN  direction_t;
        
        dist_bound : OUT unsigned(length-1 downto 0)
    );
END CalcDistGeometry;

ARCHITECTURE Structural OF CalcDistGeometry IS
    -- Definizione geometria box [-L, +L]
    -- ESEMPIO: 100.0 cm (in Q16.48 => 100 * 2^48)
    -- Hex: 0x0064_0000_0000_0000
    constant BOX_LIMIT : signed(length-1 downto 0) := x"0064000000000000";
    
    -- Segnali per i numeratori (Numeratori)
    signal num_x, num_y, num_z : signed(length-1 downto 0);
    
    -- Risultati Divisione
    signal dist_x_s, dist_y_s, dist_z_s : signed(length-1 downto 0);
    signal dist_x, dist_y, dist_z       : unsigned(length-1 downto 0);
    
BEGIN

    -- 1. PRE-CALCOLO NUMERATORI (Sottrazione)
    --    Se vuoi usare un Custom Adder/Subtractor, sostituisci questo blocco.
    process(position, direction)
    begin
        -- X
        if direction.vx > 0 then num_x <= BOX_LIMIT - position.x;
        elsif direction.vx < 0 then num_x <= (-BOX_LIMIT) - position.x;
        else num_x <= (others => '0'); end if;

        -- Y
        if direction.vy > 0 then num_y <= BOX_LIMIT - position.y;
        elsif direction.vy < 0 then num_y <= (-BOX_LIMIT) - position.y;
        else num_y <= (others => '0'); end if;

        -- Z
        if direction.vz > 0 then num_z <= BOX_LIMIT - position.z;
        elsif direction.vz < 0 then num_z <= (-BOX_LIMIT) - position.z;
        else num_z <= (others => '0'); end if;
    end process;


    -- 2. ISTANZE DIVISORI (Custom Implementation)
    --    Nota: Qui istanziamo 3 divisori in parallelo per throughput.
    
    Inst_DivX: entity work.divr2
    PORT MAP (
        clk => clk,
        rst => rst, 
        
        dividend => unsigned(std_logic_vector(num_x)), -- Assumiamo input unsigned o gestiamo segno dentro
        divisor  => unsigned(std_logic_vector(direction.vx)),
        quotient => open -- map to signed conversion logic
    );
    -- Mockup connection per compilazione:
    -- In realtà, va collegato l'output del custom divider a 'dist_x_s'
    -- Qui mantengo l'operatore comportamentale SOLO come placeholder se il componente non c'è.
    -- Sostituisci con output reale.
    
    -- Per ora, per non rompere la simulazione senza i file Custom,
    -- Lascio il behavioral wrappato con SCALING CORRETTO per Q16.48.
    
    process(num_x, direction.vx) 
        variable v_num : signed(127 downto 0);
        variable v_den : signed(127 downto 0);
        variable v_res : signed(127 downto 0);
    begin
        if direction.vx /= 0 then 
            -- Scaling: (Num * 2^48) / Den
            v_num := resize(num_x, 128) sll 48;
            v_den := resize(direction.vx, 128);
            v_res := v_num / v_den;
            dist_x_s <= resize(v_res, length); -- Clamp/Truncate to 64 bit
        else 
            dist_x_s <= (others => '0');
            dist_x_s(length-2) <= '1'; -- Large Positive
        end if;
    end process;

    process(num_y, direction.vy) 
        variable v_num : signed(127 downto 0);
        variable v_den : signed(127 downto 0);
        variable v_res : signed(127 downto 0);
    begin
        if direction.vy /= 0 then 
            v_num := resize(num_y, 128) sll 48;
            v_den := resize(direction.vy, 128);
            v_res := v_num / v_den;
            dist_y_s <= resize(v_res, length);
        else 
             dist_y_s <= (others => '0');
             dist_y_s(length-2) <= '1';
        end if;
    end process;
    
    process(num_z, direction.vz) 
        variable v_num : signed(127 downto 0);
        variable v_den : signed(127 downto 0);
        variable v_res : signed(127 downto 0);
    begin
        if direction.vz /= 0 then 
            v_num := resize(num_z, 128) sll 48;
            v_den := resize(direction.vz, 128);
            v_res := v_num / v_den;
            dist_z_s <= resize(v_res, length);
        else 
             dist_z_s <= (others => '0');
             dist_z_s(length-2) <= '1';
        end if;
    end process;


    -- 3. MINIMO e OUTPUT
    process(dist_x_s, dist_y_s, dist_z_s)
        variable min_v : unsigned(length-1 downto 0);
        variable dx, dy, dz : unsigned(length-1 downto 0);
    begin
        -- Clamp negativi (non dovrebbero esserci se inside box)
        if dist_x_s < 0 then dx := (others => '0'); else dx := unsigned(dist_x_s); end if;
        if dist_y_s < 0 then dy := (others => '0'); else dy := unsigned(dist_y_s); end if;
        if dist_z_s < 0 then dz := (others => '0'); else dz := unsigned(dist_z_s); end if;
        
        -- Minimo
        min_v := dx;
        if dy < min_v then min_v := dy; end if;
        if dz < min_v then min_v := dz; end if;
        
        dist_bound <= min_v;
    end process;

END Structural;

