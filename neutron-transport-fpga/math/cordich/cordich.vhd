library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.config.all; -- Access to global configuration constants
use work.configcordic.all; -- Access to atanhlut and constants
use work.configcordich.all; -- Access to m_maxiterh and related constants


----------------------------------------------------------------------------------
-- Entity: cordich
-- Description:
--   Hyperbolic CORDIC Processor (Pipelined).
--   Computes Hyperbolic functions (sinh, cosh, atanh, ln, sqrt) based on mode.
--
-- Architecture:
--   Unrolled pipeline of CORDIC stages.
--   Includes NEGATIVE iterations (i <= 0) essential for convergence in Hyperbolic mode.
--   Includes POSITIVE iterations (i > 0).
--
-- Generics:
--   mode: 'm_vectoring' (calculates angle/log) or 'm_rotating' (calculates vector/exp).
----------------------------------------------------------------------------------
entity cordich is
    generic (
        mode : cordicmode_t := m_vectoring
    );
    port (
        clk      : in  std_logic;
        rst    : in  std_logic;
        
        statein  : in  cordicstate_t;  -- Initial X, Y, Z
        stateout : out cordicstate_t   -- Final X, Y, Z
    );
end entity cordich;

architecture rtl of cordich is
    type cordichpipe_t is array (0 to m_maxiterh) of cordicstate_t;
    signal stages    : cordichpipe_t := (others => ((others => '0'), (others => '0'), (others => '0'))); -- combinatorial output
    -- signal statgesreg : cordichpipe_t;

begin
    stages(0) <= statein;
    genstagesneg: for i in 0 to m_negiter generate
        inst_neg : entity work.negcordicstageh
            generic map (
                iter => atanhlut(i).index,
                mode => mode
            )
            port map (
                clk      => clk,
                rst      => rst,
                statein  => stages(i),
                phi      => atanhlut(i).value,
                stateout => stages(i + 1)
            );
    end generate genstagesneg;

    genstagespos: for i in m_negiter + 1 to m_maxiterh - 1 generate 
        inst_pos : entity work.poscordicstageh
            generic map (
                iter => atanhlut(i).index,
                mode => mode
            )
            port map (
                clk      => clk,
                rst      => rst,
                statein  => stages(i),
                phi      => atanhlut(i).value,
                stateout => stages(i + 1)
            );
    end generate genstagespos;

    -- Output Connection
    stateout <= stages(stages'high);

end architecture rtl;
