library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use ieee.std_logic_textio.all;
use work.config.all;
use work.configcordic.all;
use work.configopenmc.all;

----------------------------------------------------------------------------------
-- Entity: geometryworker
-- Description: 
--   Calculates the distance to the nearest boundary (Ray Tracing) and compares
--   it with the pre-calculated collision distance.
--   Determines if the next event is a COLLISION or a SURFACE CROSSING.
--
-- Geometry: 
--   Currently hardcoded as a Cube centered at (0,0,0).
--   Boundary Limits are defined by constant BOUNDARY_LIMIT.
--   Logic assumes axes-aligned planes (X-plane, Y-plane, Z-plane).
--
-- Latency:
--   The module uses deep pipelined dividers (divr2).
--   To maintain data consistency, the particle record travels through a 
--   shift register (p_pipe) matching the divider latency.
----------------------------------------------------------------------------------
entity geometryworker is 
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;

        busy        : out std_logic;      -- Backpressure signal (currently unused, tied to '0')
        validin     : in  std_logic;      -- Input Validity
        particlein  : in  particle_t;     -- Input Particle Record (contains Pos, Dir, Dist_Coll)

        validout    : out std_logic;      -- Output Validity
        particleout : out particle_t      -- Output Particle (Updated nextop, dist_coll, dist_bound)
    );
end entity geometryworker;


architecture behavioral of geometryworker is

    -- Helper function to safely convert ID to integer for logging
    -- Handles large IDs by taking only lower bits that fit in integer range
    function safe_id_to_int(id_vec : std_logic_vector) return integer is
        variable v_low_bits : unsigned(30 downto 0);
    begin
        if id_vec'length >= 31 then
            v_low_bits := unsigned(id_vec(30 downto 0));
        else
            v_low_bits := resize(unsigned(id_vec), 31);
        end if;
        return to_integer(v_low_bits);
    end function;

    -- Geometry Constants (Cube 1.0 in Q16.48)
    -- Changed from tiny value to 1.0 to check Collisions
    constant BOUNDARY_LIMIT : signed(length-1 downto 0) := x"0001000000000000";
    
    -- Divider Component
    -- Used to calculate Distance = (Boundary - Position) / Direction
    component divr2 is
        port (
            clk      : IN  std_logic;
            rst      : IN  std_logic;
            dividend : IN  unsigned(length-1 downto 0);
            divisor  : IN  unsigned(length-1 downto 0);
            quotient : OUT unsigned(length-1 downto 0)
        );
    end component;

    -- Pipeline Signals
    -- Must match the latency of divr2 (length = 64 bits = 64 cycles)
    constant PIPELINE_DEPTH : integer := length; 
    
    type particle_pipeline_t is array (0 to PIPELINE_DEPTH) of particle_t;
    signal p_pipe : particle_pipeline_t;
    
    signal valid_pipe : std_logic_vector(0 to PIPELINE_DEPTH);
    
    -- Divider Inputs (Numerators and Denominators for X, Y, Z axes)
    signal num_x, num_y, num_z : unsigned(length-1 downto 0);
    signal den_x, den_y, den_z : unsigned(length-1 downto 0);
    
    -- Divider Outputs (Calculated distances to X, Y, Z planes)
    signal dist_x_raw, dist_y_raw, dist_z_raw : unsigned(length-1 downto 0);
    signal quot_x, quot_y, quot_z : unsigned(length-1 downto 0);
    
    -- Internal signals for the comparison stage (post-divider)
    signal d_coll_final    : unsigned(length-1 downto 0);
    signal d_bound_final   : unsigned(length-1 downto 0);
    
    -- Constant for infinite boundary
    constant INF_DIST : unsigned(length-1 downto 0) := (others => '1');

    file track_file : text open write_mode is "track2.log";

begin

    busy <= '0';

    -------------------------------------------------------
    -- Process: Pipeline Shift Register
    -- Purpose: Delays the particle data to match the latency
    --          of the hardware dividers.
    -------------------------------------------------------
    process(clk, rst)
    begin
        if rst = '1' then
            valid_pipe <= (others => '0');
            for i in 0 to PIPELINE_DEPTH loop
                p_pipe(i) <= EMPTYPARTICLE;
            end loop;
        elsif rising_edge(clk) then
            if validin = '1' then
                p_pipe(0) <= particlein;
            end if;
            valid_pipe(0) <= validin;
            
            for i in 0 to PIPELINE_DEPTH-1 loop
                p_pipe(i+1) <= p_pipe(i);
                valid_pipe(i+1) <= valid_pipe(i);
            end loop;
        end if;
    end process;


    -------------------------------------------------------
    -- Process: Pre-Calculation (Ray Tracing Setup)
    -- Purpose: Determines the numerator (Distance to plane)
    --          and denominator (Direction) for each axis.
    -- Logic:   d = (Boundary_Pos - Particle_Pos) / Direction
    -------------------------------------------------------
    process(particlein)
        variable diff : signed(length-1 downto 0);
        variable v_den : signed(length-1 downto 0);
    begin
        
        -- Default assignments to avoid latches
        num_x <= (others => '1'); den_x <= to_unsigned(1, length);
        num_y <= (others => '1'); den_y <= to_unsigned(1, length);
        num_z <= (others => '1'); den_z <= to_unsigned(1, length);

        -- X Axis Calculation
        if particlein.direction.vx > 0 then
            -- Moving +X: Distance to Max X Boundary
            -- Dist = (Limit - x)
            diff := BOUNDARY_LIMIT - particlein.position.x;
            if diff < 0 then num_x <= (others => '0'); else num_x <= unsigned(diff); end if;
            den_x <= unsigned(particlein.direction.vx);
        elsif particlein.direction.vx < 0 then
            -- Moving -X: Distance to Min X Boundary (-Limit)
            -- Dist = x - (-Limit) = x + Limit
            diff := particlein.position.x + BOUNDARY_LIMIT;
            if diff < 0 then num_x <= (others => '0'); else num_x <= unsigned(diff); end if;
             -- Absolute value of direction for unsigned division
            v_den := -particlein.direction.vx;
            den_x <= unsigned(v_den);
        end if;
        
        -- Y Axis Calculation
        if particlein.direction.vy > 0 then
            diff := BOUNDARY_LIMIT - particlein.position.y;
            if diff < 0 then num_y <= (others => '0'); else num_y <= unsigned(diff); end if;
            den_y <= unsigned(particlein.direction.vy);
        elsif particlein.direction.vy < 0 then
            diff := particlein.position.y + BOUNDARY_LIMIT;
            if diff < 0 then num_y <= (others => '0'); else num_y <= unsigned(diff); end if;
            v_den := -particlein.direction.vy;
            den_y <= unsigned(v_den);
        end if;

        -- Z Axis Calculation
        if particlein.direction.vz > 0 then
            diff := BOUNDARY_LIMIT - particlein.position.z;
            if diff < 0 then num_z <= (others => '0'); else num_z <= unsigned(diff); end if;
            den_z <= unsigned(particlein.direction.vz);
        elsif particlein.direction.vz < 0 then
            diff := particlein.position.z + BOUNDARY_LIMIT;
            if diff < 0 then num_z <= (others => '0'); else num_z <= unsigned(diff); end if;
            v_den := -particlein.direction.vz;
            den_z <= unsigned(v_den);
        end if;
    end process;


    -------------------------------------------------------
    -- Component Instantiation: Dividers
    -- Purpose: Calculate intersection distance for each axis in parallel.
    -------------------------------------------------------
    DivX : divr2 port map (clk => clk, rst => rst, dividend => num_x, divisor => den_x, quotient => quot_x);
    DivY : divr2 port map (clk => clk, rst => rst, dividend => num_y, divisor => den_y, quotient => quot_y);
    DivZ : divr2 port map (clk => clk, rst => rst, dividend => num_z, divisor => den_z, quotient => quot_z);
    
    -- FIXED POINT CORRECTION:
    -- Integer Division A / B returns integer ratio.
    -- For Q16.48 result, we must shift left by 48 (multiply by 2^48).
    -- Limitation: If integer result >= 2^16, this overflows (Distance > 65535).
    dist_x_raw <= quot_x sll 48;
    dist_y_raw <= quot_y sll 48;
    dist_z_raw <= quot_z sll 48;


    -------------------------------------------------------
    -- Process: Post-Division Logic
    -- Purpose: 1. Find min(dist_x, dist_y, dist_z) -> dist_boundary.
    --          2. Compare dist_boundary vs dist_collision.
    --          3. Update particle state/distances.
    -------------------------------------------------------
    process(clk, rst)
        variable candidate_bound : unsigned(length-1 downto 0);
        variable v_p : particle_t;
        variable d_travel : unsigned(length-1 downto 0);
        variable mult_res_x : signed(2*length-1 downto 0);
        variable mult_res_y : signed(2*length-1 downto 0);
        variable mult_res_z : signed(2*length-1 downto 0);

        variable v_line     : line;
    begin
        if rst = '1' then
            validout <= '0';
            particleout <= EMPTYPARTICLE;
        elsif rising_edge(clk) then
            
            -- Read from end of pipeline
            v_p := p_pipe(PIPELINE_DEPTH);

            if valid_pipe(PIPELINE_DEPTH) = '1' then
                
                -- Determine Minimum Boundary Distance
                candidate_bound := dist_x_raw;
                if dist_y_raw < candidate_bound then
                    candidate_bound := dist_y_raw;
                end if;
                if dist_z_raw < candidate_bound then
                    candidate_bound := dist_z_raw;
                end if;
                
                -- Comparison Logic
                if v_p.dist_collision < candidate_bound then
                    -- CASE 1: COLLISION
                    d_travel := v_p.dist_collision;
                    
                    v_p.nextop := OP_COLLISION;
                    v_p.dist_boundary := candidate_bound - v_p.dist_collision;
                    v_p.dist_collision := (others => '0');
                else
                    -- CASE 2: SURFACE CROSSING
                    d_travel := candidate_bound; 

                    v_p.nextop := OP_CROSS_SURFACE;
                    v_p.dist_collision := v_p.dist_collision - candidate_bound;
                    v_p.dist_boundary := (others => '0');
                end if;
                
                -- POSITION UPDATE: P_new = P_old + d * dir
                -- Q16.48 * Q16.48 -> Q32.96. Slice [111 downto 48] for Q16.48.
                mult_res_x := v_p.direction.vx * signed(d_travel);
                v_p.position.x := v_p.position.x + mult_res_x(111 downto 48);
                
                mult_res_y := v_p.direction.vy * signed(d_travel);
                v_p.position.y := v_p.position.y + mult_res_y(111 downto 48);
                
                mult_res_z := v_p.direction.vz * signed(d_travel);
                v_p.position.z := v_p.position.z + mult_res_z(111 downto 48);

                -- LOGGING PARTICLE 2
                if safe_id_to_int(v_p.id) = 10 then
                    write(v_line, string'("Time: "));
                    write(v_line, now);
                    write(v_line, string'(" Event: "));
                    if v_p.nextop = OP_COLLISION then
                        write(v_line, string'("COLLISION"));
                    else
                        write(v_line, string'("CROSS_SURF"));
                    end if;
                    write(v_line, string'(" d_travel: "));
                    hwrite(v_line, d_travel);
                    write(v_line, string'(" Pos X: "));
                    hwrite(v_line, v_p.position.x);
                    write(v_line, string'(" Pos Y: "));
                    hwrite(v_line, v_p.position.y);
                    write(v_line, string'(" Pos Z: "));
                    hwrite(v_line, v_p.position.z);
                    writeline(track_file, v_line);
                end if;

                particleout <= v_p;
                validout <= '1';

            else
                validout <= '0';
            end if;
            
        end if;
    end process;

end architecture behavioral;
                    