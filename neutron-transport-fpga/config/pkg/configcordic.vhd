library ieee; 
use ieee.std_logic_1164.all; 
use ieee.numeric_std.all; 
use work.config.all; 

--! @file configcordic.vhd
--! @brief Package di tipi e costanti per la pipeline CORDIC.
--! @author Gian Marco Coppari
--! @date 2026/02/10

--! @package configcordic
--! Tipi e costanti per la configurazione della pipeline CORDIC.
package configcordic is 

    --! @enum cordicmode_t
    --! Modalità operative del CORDIC: rotazionale o vettoriale.
    type cordicmode_t is (m_rotating, m_vectoring); 

    --! @struct cordicstate_t
    --! Stato interno della pipeline CORDIC (coordinate x, y, z).
    type cordicstate_t is record 
        --! Coordinata x (Qm formato, larghezza totale: m_blocksize * m_blocks)
        x : signed(m_blocksize * m_blocks - 1 downto 0);

        --! Coordinata y (Qm formato, larghezza totale: m_blocksize * m_blocks)
        y : signed(m_blocksize * m_blocks - 1 downto 0);

        --! Coordinata z (Qm formato, larghezza totale: m_blocksize * m_blocks)
        z : signed(m_blocksize * m_blocks - 1 downto 0);
    end record cordicstate_t;
end package configcordic; 

--! @brief Corpo vuoto del package configcordic.
package body configcordic is
end package body configcordic;
