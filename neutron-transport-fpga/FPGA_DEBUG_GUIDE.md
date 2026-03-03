# Guida Debug ID su FPGA con VIO/ILA

## Problema

In simulazione gli ID funzionano correttamente (sequenza 8, 16, 24, 32...), ma su FPGA reale con VIO/ILA di Vivado non si vedono.

## Causa

I segnali `particleout.id` e `finished_valid` cambiano molto rapidamente (ogni ~145 cicli). Senza trigger/cattura corretta, l'ID visualizzato cambia troppo velocemente per essere letto.

## Soluzione: Configurare ILA Correttamente

### Setup ILA in Vivado Hardware Manager

1. **Aprire Hardware Manager** in Vivado
2. **Program Device** con il bitstream
3. **Aprire ILA Dashboard**

### Configurazione Trigger ILA

**Obiettivo**: Catturare l'ID quando una particella finisce (`finished_valid='1`)

#### Trigger Settings:

```
Probe: probe7 (finished_valid)
Trigger Condition: == 1'b1
Trigger Position: 512 (center window)
Window Depth: 1024 samples
```

#### Probe Mapping (da top.vhd linee 217-229):
- **probe0**: particleout.alive
- **probe1**: nextop
- **probe2**: fabs (absorption flag)
- **probe3**: ffiss (fission flag)  
- **probe4**: fleakage (leakage flag)
- **probe5**: **particleout.id** ← QUESTO È L'ID!
- **probe6**: busy
- **probe7**: **finished_valid** ← USA QUESTO COME TRIGGER

### Procedura Cattura:

1. **Set Trigger**:
   ```
   probe7 (finished_valid) == 1
   ```

2. **Arm Trigger**: Click "Run Trigger"

3. **Iniettare Particelle** via VIO:
   - Setta `probe_out1` (inject_valid) = 1
   - Setta `probe_out3` (particlein.id) = 0x0000000000000008 (ID=8)
   - Setta altri campi particella (posizione, direzione, energia)
   - Pulse inject

4. **Aspettare Trigger**: ILA catturerà quando finished_valid='1'

5. **Leggere ID** in probe5 della waveform ILA

### Leggere ID in VIO (Alternativa Semplice)

**Problema**: VIO aggiorna in real-time, troppo veloce per leggere.

**Soluzione**: Vedi sezione "Registro di Cattura" sotto.

## Soluzione Avanzata: Registro di Cattura ID

Per facilitare la lettura, aggiungi un registro che "blocca" l'ultimo ID finito.

### Modifica top.vhd:

Aggiungi dopo la linea 120:

```vhdl
-- Registro cattura ultimo ID finito
signal last_finished_id : std_logic_vector(63 downto 0) := (others => '0');
signal capture_counter : unsigned(31 downto 0) := (others => '0');
```

Aggiungi processo di cattura prima di `end architecture`:

```vhdl
-- Processo cattura ID quando finished_valid='1'
process(clk)
begin
    if rising_edge(clk) then
        if rst = '1' then
            last_finished_id <= (others => '0');
            capture_counter <= (others => '0');
        elsif finished_valid = '1' then
            last_finished_id <= particleout.id;
            capture_counter <= capture_counter + 1;
        end if;
    end if;
end process;
```

Modifica VIO per esporre questi segnali:

```vhdl
probe_in17 => last_finished_id,     -- Nuovo: ultimo ID catturato
probe_in18 => std_logic_vector(capture_counter(31 downto 0)), -- Contatore particelle finite
```

**Vantaggio**: `last_finished_id` rimane stabile e leggibile in VIO anche dopo che `particleout.id` cambia.

## Verifica Funzionamento

### Test 1: Iniettare Singola Particella

1. Via VIO, inietta particella con ID=8:
   ```
   probe_out1 (inject_valid) = 1
   probe_out3 (particlein.id) = 0x0000000000000008
   probe_out17 (alive) = 1
   ... (altri campi)
   ```

2. Monitora in ILA o VIO:
   - Aspetta ~145 cicli (latenza pipeline)
   - Quando `finished_valid=1`, leggi `probe5` (ID output)

3. **Aspettativa**: 
   - Se NO fissione: ID output = 0x0000000000000008 (uguale input)
   - Se fissione: ID output = 0x0000000000000040 (8*8=64) o multipli

### Test 2: Burst di Particelle

Inietta rapidamente 10 particelle (ID = 8, 16, 24, 32...):

```
For i in 1 to 10:
  probe_out3 = i * 8
  probe_out1 = 1 (pulse)
```

Usa ILA per catturare stream di finished_valid pulses.

### Interpretazione Risultati

| Osservazione | Significato |
|--------------|-------------|
| ID output = ID input | Particella assorbita/leaked senza fissione |
| ID output = ID input × 8 + offset | Particella figlia da fissione (Parent × 8 + index) |
| ID output = 0 | BUG! (Non dovrebbe succedere con le fix applicate) |
| finished_valid non si attiva mai | Possibile problema pipeline/clock |

## Troubleshooting

### Non Vedo finished_valid='1'

**Causa**: Particelle potrebbero loopare infinitamente o pipeline bloccata.

**Debug**:
- Controlla `busy` in VIO: dovrebbe diventare '1' quando particelle in sistema
- Controlla ILA probe0 (alive): dovrebbe essere '1' mentre processa
- Verifica clock sta funzionando (probe clk in ILA)

### ID Sempre Zero

**Causa**: Bug overflow fissione o problema iniezione.

**Debug**:
- Verifica in ILA se ffiss (probe3) si attiva
- Se fissione avviene, controlla eventworker.vhd per log debug
- Verifica particlein.id sia settato correttamente nel VIO

### ID Cambia Troppo Veloce in VIO

**Soluzione**: Usa registro cattura (vedi sopra) o usa ILA con trigger.

## Configurazione Ottimale ILA

### Settings Raccomandati:

```
Capture Mode: BASIC
Window Depth: 2048 samples (sufficiente per vedere ~14 particelle)
Trigger Mode: BASIC_ONLY
Trigger Position: 1024 (centro finestra)

Trigger Conditions:
  - probe7 (finished_valid) == 1
  
Display Radix per probe5 (ID):
  - Hex (per vedere 8, 10, 18, 20...)
  - O Unsigned Decimal (per vedere 8, 16, 24, 32...)
```

### Probes da Monitorare:

- **probe5 (ID)**: Valore principale
- **probe7 (finished_valid)**: Trigger e validità dato
- **probe3 (ffiss)**: Indica se fissione avvenuta
- **probe2 (fabs)**: Indica se assorbimento
- **probe4 (fleakage)**: Indica se leakage
- **probe1 (nextop)**: Stato finale operazione

## Comandi TCL per Automazione

Se usi Vivado TCL console:

```tcl
# Connect to hardware
open_hw_manager
connect_hw_server
open_hw_target

# Program device
set_property PROGRAM.FILE {path/to/design.bit} [current_hw_device]
program_hw_devices [current_hw_device]

# Configure ILA
set ila [get_hw_ilas]
set_property TRIGGER_COMPARE_VALUE eq1'b1 [get_hw_probes probe7 -of_objects $ila]
set_property CONTROL.TRIGGER_POSITION 512 $ila
run_hw_ila $ila

# Wait for trigger
wait_on_hw_ila $ila

# Display waveform
display_hw_ila_data [current_hw_ila_data]
```

## Conclusione

Con ILA configurato correttamente dovresti vedere:
- **Input ID**: 8, 16, 24, 32, 40... (hex: 8, 10, 18, 20, 28...)
- **Output ID**: Stesso valore O derivato da fissione (Parent*8+index)
- **Nessun ID zero** (grazie alle protezioni in eventworker.vhd)

Il codice funziona correttamente in simulazione, quindi il problema è solo di visualizzazione/cattura in hardware.
