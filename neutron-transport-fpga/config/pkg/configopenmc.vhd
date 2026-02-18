LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;
use work.config.all;


package configopenmc is
    type material_t is (VOID, FUEL); -- MIXUUB è la miscela di Uranio235, Uranio238 e Boro10
                                       -- materiale macroscopico
                                       
    type nuclide_t is (NONE, U235, U238, B10); -- nuclide per l'interazione, 
                                         -- diverso da materiale macroscopico
    
    function ToMaterial(idx : integer) return material_t;
    function ToIntMaterial(mat : material_t) return integer;
   
    function ToNuclide(idx : integer) return nuclide_t;
    function ToIntNuclide(nucl : nuclide_t) return integer;

    -- Mock Function to replace lost 'xs' package functionality for now
    -- Returns 1/Sigma_total (fixed values for testing)
    -- Using m_blocksize * m_blocks width (matches particle_t fields)
    function get_inv_sigma(mat : material_t) return unsigned;

    -- Tipi di Operazioni per la Pipeline
    type operation_t is (
        OP_INIT, 
        OP_XS_LOOKUP, 
        OP_ADVANCE,       
        OP_CROSS_SURFACE, 
        OP_COLLISION, 
        OP_TALLY, 
        OP_DYING
    );
   
    function ToOperation(idx : integer) return operation_t;
    function ToIntOperation(op : operation_t) return integer;

    type position_t is record 
        x : signed(m_blocksize * m_blocks - 1 downto 0);
        y : signed(m_blocksize * m_blocks - 1 downto 0);
        z : signed(m_blocksize * m_blocks - 1 downto 0);
    end record position_t;
    
    type direction_t is record
        vx : signed(m_blocksize * m_blocks - 1 downto 0);
        vy : signed(m_blocksize * m_blocks - 1 downto 0);
        vz : signed(m_blocksize * m_blocks - 1 downto 0);
    end record direction_t;
    
    
    constant ncells : integer := 10; -- numero a caso
    constant strlength : integer := 64; -- lunghezza id particella (AUMENTATA per evitare overflow)
    type particle_t is record
        id        : std_logic_vector(strlength - 1 downto 0); -- si può convertire in std_logic_vector
        position  : position_t;
        direction : direction_t;
        energy    : unsigned(m_blocksize * m_blocks - 1 downto 0);
        material  : material_t; -- enumerazione
        cellid    : std_logic_vector(ncells - 1 downto 0);
        
        dist_collision : unsigned(m_blocksize * m_blocks - 1 downto 0); -- distanza alla prossima collisione
        dist_boundary  : unsigned(m_blocksize * m_blocks - 1 downto 0); -- distanza all'eventuale bordo

        nextop    : operation_t; 
        weight    : unsigned(m_blocksize * m_blocks - 1 downto 0);
        alive     : std_logic; 
    end record particle_t; 

    constant EMPTYPARTICLE : particle_t := (
        id        => (others => '0'),
        position  => (x => (others => '0'), y => (others => '0'), z => (others => '0')),
        direction => (vx => (others => '0'), vy => (others => '0'), vz => (others => '0')),
        energy    => (others => '0'),
        material  => FUEL, -- default a FUEL per evitare problemi di logica con VOID (es. inv sigma infinito)
                           -- TODO: future refactoring: separate material from particle state check OpenMC software structure
        cellid    => (others => '1'),
        dist_collision  => (others => '0'),
        dist_boundary   => (others => '0'),
        nextop    => OP_INIT,
        weight    => (others => '0'),
        alive     => '0'
    );

end package configopenmc;


package body configopenmc is
    function ToMaterial(idx : integer) return material_t is 
    begin 
        case idx is
            when 0      => return VOID;
            when 1      => return FUEL;
            when others => return VOID; -- safe default
        end case;
    end function ToMaterial;
    
    function ToIntMaterial(mat : material_t) return integer is 
    begin 
        case mat is 
            when VOID   => return 0;
            when FUEL   => return 1;
            when others => return 0; -- safe default
        end case;
    end function ToIntMaterial;
    

    function ToNuclide(idx : integer) return nuclide_t is begin 
        case idx is
            when 0      => return NONE;
            when 1      => return U235;
            when 2      => return U238;
            when 3      => return B10;
            when others => return NONE; -- safe default
        end case;
    end function ToNuclide;
    function ToIntNuclide(nucl : nuclide_t) return integer is begin 
        case nucl is 
            when NONE  => return 0;
            when U235  => return 1;
            when U238  => return 2;
            when B10   => return 3;
            when others=> return 0; -- safe default
        end case;
    end function ToIntNuclide;

    function get_inv_sigma(mat : material_t) return unsigned is
         -- Assuming 32-bit fixed point for now (length constant from physicsworker is tricky here)
         -- We use m_blocksize * m_blocks from config
         variable res : unsigned(m_blocksize * m_blocks - 1 downto 0);
    begin
         -- Mock Values
         if mat = FUEL then
             -- E.g. Sigma = 1.0 -> Inv = 1.0
             -- Format Q16.48 (64 bit total).
             -- Bit 48 is the weight 2^0 = 1.0.
             res := (others => '0');
             res(48) := '1'; 
         else
             -- VOID -> Infinite distance (Inv Sigma very large)
             res := (others => '1');
         end if;
         return res;
    end function;

    -- utility per conversione in std_logic_vector
    -- necessarie per vio Vivado, che non supporta tipi enumerati nei record
    function ToOperation(idx : integer) return operation_t is
    begin 
        case idx is
            when 0 => return OP_INIT;
            when 1 => return OP_XS_LOOKUP;
            when 2 => return OP_ADVANCE;
            when 3 => return OP_CROSS_SURFACE;
            when 4 => return OP_COLLISION;
            when 5 => return OP_TALLY;
            when 6 => return OP_DYING;
            when others => return OP_DYING; -- safe default
        end case;
    end function ToOperation;

    function ToIntOperation(op : operation_t) return integer is
    begin 
        case op is 
            when OP_INIT          => return 0;
            when OP_XS_LOOKUP     => return 1;
            when OP_ADVANCE       => return 2;
            when OP_CROSS_SURFACE => return 3;
            when OP_COLLISION     => return 4;
            when OP_TALLY         => return 5;
            when OP_DYING         => return 6;
            when others           => return 6; -- safe default
        end case;
    end function ToIntOperation;

        
end package body configopenmc;