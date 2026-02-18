library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.config.all;
use work.configcordic.all;
use work.configcordicc.all;


entity cordicc is 
    port (
        clk      : in  std_logic;
        rst      : in  std_logic;

        statein  : in  cordicstate_t;
        stateout : out cordicstate_t
    );
end entity cordicc;


architecture rtl of cordicc is 
    type cordiccpipe_t is array (0 to m_maxiterc) of cordicstate_t;
    signal stages : cordiccpipe_t := (others => ((others => '0'), (others => '0'), (others => '0'))); -- combinatorial output

begin   
    -- combinatorial assignment of first stage
    stages(0) <= statein;

    -- compute intermediate stages
    genstages: for i in 0 to m_maxiterc - 1 generate 
        cstage : entity work.cordicstagec(rtl)
            generic map ( iter => i )
            port map (
                clk      => clk,
                rst      => rst,

                statein  => stages(i),
                alpha    => atanlut(i),
                stateout => stages(i + 1)
            );
    end generate genstages;

    -- Output Connection
    stateout <= stages(stages'high);

end architecture rtl;