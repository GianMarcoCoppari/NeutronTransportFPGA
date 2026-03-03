library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.config.all;
use work.configcordic.all;
use work.configopenmc.all;
use work.xs.all;


entity top is 
    port (
        clk_n : in std_logic;
        clk_p : in std_logic
    );
end entity top;

architecture behavioral of top is
    -- clock component
    component clk_wiz_0
        port (
            -- Clock in ports
            -- Clock out ports
            clk_out1  : out std_logic;
            
            -- Status and control signals
            reset     : in  std_logic;
            locked    : out std_logic;
            clk_in1_p : in  std_logic;
            clk_in1_n : in  std_logic
        );
    end component clk_wiz_0;
    
    
    -- vio component  
    component vio_0
        port (
            clk         : in  std_logic;
            probe_in0   : in  std_logic_vector(0  downto 0);
            probe_in1   : in  std_logic_vector(0  downto 0);
            probe_in2   : in  std_logic_vector(63 downto 0);
            probe_in3   : in  std_logic_vector(63 downto 0);
            probe_in4   : in  std_logic_vector(63 downto 0);
            probe_in5   : in  std_logic_vector(63 downto 0);
            probe_in6   : in  std_logic_vector(63 downto 0);
            probe_in7   : in  std_logic_vector(63 downto 0);
            probe_in8   : in  std_logic_vector(63 downto 0);
            probe_in9   : in  std_logic_vector(63 downto 0);
            probe_in10  : in  std_logic_vector(31 downto 0);
            probe_in11  : in  std_logic_vector(9  downto 0);
            probe_in12  : in  std_logic_vector(63 downto 0);
            probe_in13  : in  std_logic_vector(63 downto 0);
            probe_in14  : in  std_logic_vector(31 downto 0);
            probe_in15  : in  std_logic_vector(63 downto 0);
            probe_in16  : in  std_logic_vector(0  downto 0);
        
            probe_out0  : out std_logic_vector(0  downto 0);
            probe_out1  : out std_logic_vector(0  downto 0);
            probe_out2  : out std_logic_vector(0  downto 0);
            probe_out3  : out std_logic_vector(63 downto 0);
            probe_out4  : out std_logic_vector(63 downto 0);
            probe_out5  : out std_logic_vector(63 downto 0);
            probe_out6  : out std_logic_vector(63 downto 0);
            probe_out7  : out std_logic_vector(63 downto 0);
            probe_out8  : out std_logic_vector(63 downto 0);
            probe_out9  : out std_logic_vector(63 downto 0);
            probe_out10 : out std_logic_vector(63 downto 0);
            probe_out11 : out std_logic_vector(31 downto 0);
            probe_out12 : out std_logic_vector(9  downto 0);
            probe_out13 : out std_logic_vector(63 downto 0);
            probe_out14 : out std_logic_vector(63 downto 0);
            probe_out15 : out std_logic_vector(31 downto 0);
            probe_out16 : out std_logic_vector(63 downto 0);
            probe_out17 : out std_logic_vector(0  downto 0) 
        );
    end component;
    
    -- ila component
    component ila_0
        port (
            clk : IN STD_LOGIC;
        
            probe0 : IN STD_LOGIC_VECTOR(0 DOWNTO 0);  -- alive
            probe1 : IN STD_LOGIC_VECTOR(31 DOWNTO 0); -- nextop
            probe2 : IN STD_LOGIC_VECTOR(0 DOWNTO 0);  -- capture
            probe3 : IN STD_LOGIC_VECTOR(0 DOWNTO 0);  -- fission
            probe4 : IN STD_LOGIC_VECTOR(0 DOWNTO 0);  -- leakage
            probe5 : IN STD_LOGIC_VECTOR(63 DOWNTO 0); -- id
            probe6 : IN STD_LOGIC_VECTOR(0 DOWNTO 0);  -- busy
            probe7 : IN STD_LOGIC_VECTOR(0 DOWNTO 0)   -- finished
        );
    end component;


    -- temporary signals
    signal clk : std_logic; -- := '1';
    signal rst : std_logic; -- := '1';
    signal particlein, particleout : particle_t;
    signal inject_valid, finished_valid : std_logic;
    signal scheduler_ready : std_logic := '1';
    signal busy : std_logic := '0';
    
    signal xin, yin, zin : std_logic_vector(63 downto 0);
    signal vxin, vyin, vzin : std_logic_vector(63 downto 0);
    
    signal xout, yout, zout : std_logic_vector(63 downto 0);
    signal vxout, vyout, vzout : std_logic_vector(63 downto 0);
     
    signal energyinslv, energyoutslv    : std_logic_vector(63 downto 0);
    signal distcollisioninslv, distcollisionoutslv : std_logic_vector(63 downto 0);
    signal distboundaryinslv, distboundaryoutslv : std_logic_vector(63 downto 0);
    signal weightinslv, weightoutslv : std_logic_vector(63 downto 0);
    
    signal materialoutslv, nextopoutslv : std_logic_vector(31 downto 0);
    signal materialinslv, nextopinslv   : std_logic_vector(31 downto 0);
    
    signal rnd  : std_logic_vector(63 downto 0);
    
    signal ready : std_logic; 
    
    signal fscatt, fabs, ffiss, fleakage : std_logic;
    
    
begin
    -- instance clocking wizard
    clock : clk_wiz_0 
        port map (
            clk_out1  => clk, 
        
            reset     => '0', 
            locked    => open, 
            
            clk_in1_p => clk_p, 
            clk_in1_n => clk_n
        );
        
    
    -- casting dei segnali
    particlein.position.x     <= signed(xin); 
    particlein.position.y     <= signed(yin); 
    particlein.position.z     <= signed(zin); 
    particlein.direction.vx   <= signed(vxin);
    particlein.direction.vy   <= signed(vyin);
    particlein.direction.vz   <= signed(vzin);
    particlein.energy         <= unsigned(energyinslv);
    particlein.material       <= ToMaterial(to_integer(unsigned(materialinslv)));
    particlein.nextop         <= ToOperation(to_integer(unsigned(nextopinslv)));
    particlein.dist_collision <= unsigned(distcollisioninslv);
    particlein.weight         <= unsigned(weightinslv);
    particlein.dist_boundary  <= unsigned(distboundaryinslv);
    
    xout                <= std_logic_vector(particleout.position.x);
    yout                <= std_logic_vector(particleout.position.y);
    zout                <= std_logic_vector(particleout.position.z);
    vxout               <= std_logic_vector(particleout.direction.vx);
    vyout               <= std_logic_vector(particleout.direction.vy);
    vzout               <= std_logic_vector(particleout.direction.vz);
    energyoutslv        <= std_logic_vector(particleout.energy);
    distcollisionoutslv <= std_logic_vector(particleout.dist_collision);
    distboundaryoutslv  <= std_logic_vector(particleout.dist_boundary);
    weightoutslv        <= std_logic_vector(particleout.weight);
    materialoutslv      <= std_logic_vector(to_unsigned(ToIntMaterial(particleout.material), 32));
    nextopoutslv        <= std_logic_vector(to_unsigned(ToIntOperation(particleout.nextop), 32));
    
    
    -- instance virtual in/out
    vio : vio_0
        port map (
            clk => clk,
            
            -- flags
            probe_in0(0)  => busy,
            probe_in1(0)  => finished_valid,
            
            -- fpga output particle state
            probe_in2     => particleout.id,
            probe_in3     => xout,
            probe_in4     => yout,
            probe_in5     => zout,
            probe_in6     => vxout,
            probe_in7     => vyout,
            probe_in8     => vzout,
            probe_in9     => energyoutslv,
            probe_in10    => materialoutslv,
            probe_in11    => particleout.cellid,
            probe_in12    => distcollisionoutslv,
            probe_in13    => distboundaryoutslv,
            probe_in14    => nextopoutslv,
            probe_in15    => weightoutslv,
            probe_in16(0) => particleout.alive,
            
            -- rst
            probe_out0(0)  => rst,
            
            -- fpga input flags
            probe_out1(0)  => inject_valid,
            probe_out2(0)  => ready,
            
            -- fpga input particle state
            probe_out3     => particlein.id,
            probe_out4     => xin,
            probe_out5     => yin,
            probe_out6     => zin,
            probe_out7     => vxin,
            probe_out8     => vyin,
            probe_out9     => vzin,
            probe_out10    => energyinslv,
            probe_out11    => materialinslv,
            probe_out12    => particlein.cellid,
            probe_out13    => distcollisioninslv,
            probe_out14    => distboundaryinslv,
            probe_out15    => nextopinslv,
            probe_out16    => weightinslv,
            probe_out17(0) => particlein.alive
        );
        
        
    instila: ila_0
        port map (
            clk => clk, 
        
            probe0(0) => particleout.alive, -- alive
            probe1 => nextopoutslv,         -- nextop
            probe2(0) => fabs,              -- capture
            probe3(0) => ffiss,             -- fission
            probe4(0) => fleakage,          -- leakage
            probe5 => particleout.id,       -- id
            probe6(0) => busy ,             -- busy
            probe7(0) => finished_valid     -- finished
        );
    
    
    
    -- instance scheduler
    instscheduler : entity work.scheduler(rtl)
        port map (
            clk => clk, 
            rst => rst, 
            
            -- External Injection Interface (Input)
            inject_valid    => inject_valid, 
            inject_particle => particlein, 
            scheduler_ready => ready,  -- '1' se c'è spazio per iniettare
            
            -- Finished Output Interface (Output)
            -- Particelle completate (assorbite o uscite)
            finished_valid    => finished_valid, 
            finished_particle => particleout, 
            
            -- Simulator Status
            busy => busy, 
            
            fscatt   => fscatt, 
            fabs     => fabs, 
            ffiss    => ffiss, 
            fleakage => fleakage
        );

end architecture behavioral;
