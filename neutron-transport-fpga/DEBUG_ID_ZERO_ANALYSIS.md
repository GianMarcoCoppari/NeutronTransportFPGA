# Analisi Problema: particle.id = 0 durante Fissione

## Problema Riportato

Quando si iniettano 100 particelle in simulazione con ID multipli di 8 (0x8, 0x10, 0x18, 0x20...), 
si osserva `particle.id = 0` in corrispondenza degli eventi di fissione.

L'aspettativa è vedere la sequenza di ID: **8, 10, 18, 20, 28, 30...** (in esadecimale) 
nei primi 100 cicli di clock durante l'iniezione.

## Cause Possibili Identificate

### 1. **Overflow Aritmetico durante Fissione** ✅ CORRETTO

**Problema**: Nel file [`eventworker.vhd:340`](reactor/eventworker.vhd:340), l'operazione:
```vhdl
v_out.id := std_logic_vector(unsigned(v_out.id) sll 3);
```

Moltiplica l'ID del genitore per 8 (shift left 3 bit). Se l'ID è troppo grande, 
i bit superiori vengono persi causando overflow → ID = 0.

**Soluzione Applicata**:
- Controllo preventivo dei bit superiori prima dello shift
- Rilevamento e correzione se ID diventa zero
- Logging dettagliato per debug

### 2. **ID non Visualizzati Durante Iniezione** ⚠️ DA VERIFICARE

**Problema Potenziale**: L'ID potrebbe essere corretto internamente, ma non visibile 
nei log durante i primi 100 cicli a causa di:

a) **Latenza Pipeline**: La pipeline ha latenza significativa:
   - PhysicsWorker: ~80 cicli (LN + XS lookup + Mult)
   - GeometryWorker: ~64 cicli (divider)
   - EventWorker: 1-2 cicli
   - **Totale: ~145 cicli**

b) **Logging Posizionato Male**: I messaggi di debug potrebbero essere in punti 
   della pipeline dove l'ID non è ancora arrivato.

c) **Reset Accidentale**: Qualche componente potrebbe sovrascrivere l'ID con EMPTYPARTICLE.

### 3. **Problema di Formato Output** ⚠️ DA VERIFICARE

Gli ID sono stampati in esadecimale vs decimale?
- 0x8 (hex) = 8 (dec)
- 0x10 (hex) = 16 (dec)
- 0x18 (hex) = 24 (dec)

Se il monitor stampa in decimale ma ci si aspetta esadecimale, può sembrare che gli ID siano sbagliati.

## Punti di Monitoraggio Aggiunti

### File: `tb_id_propagation.vhd`

Testbench dedicato che:
1. ✅ Inietta 20 particelle con ID = i*8 (i=1..20)
2. ✅ Logga OGNI iniezione con ID in hex e decimale
3. ✅ Monitora OGNI output con ID in hex e decimale
4. ✅ Rileva automaticamente ID = 0 con alert
5. ✅ Conta particelle iniettate vs completate

### Logging Esistente Migliorato

#### In [`eventworker.vhd`](reactor/eventworker.vhd):
- Linea 343-346: Log ID base dopo shift (debug overflow)
- Linea 348-353: Alert se ID diventa zero con recovery
- Linea 291-293: Log SURFACE_LEAK con ID
- Linea 299-301: Log ABSORPTION con ID
- Linea 310-312: Log SCATTER con ID
- Linea 318-322: Log FISSION con ID genitore e nu
- Linea 344-346: Log figli fissione (immediate)
- Linea 371-374: Log figli fissione (da bank)

#### In [`physicsworker.vhd`](reactor/physicsworker.vhd):
- Linea 353-358: Log advancement con ID e distanza

#### In [`geometryworker.vhd`](reactor/geometryworker.vhd):
- Linea 269-287: Log dettagliato per particle ID=10 (esempio)

## Come Eseguire il Debug

### Passo 1: Compilare il Testbench
```bash
cd utils/neutron-transport-fpga
ghdl -a config/pkg/config.vhd
ghdl -a config/pkg/configopenmc.vhd
# ... compilare tutte le dipendenze ...
ghdl -a test/testreactor/tb_id_propagation.vhd
ghdl -e tb_id_propagation
```

### Passo 2: Eseguire la Simulazione
```bash
ghdl -r tb_id_propagation --stop-time=200us > id_debug.log 2>&1
```

### Passo 3: Analizzare i Log

#### Cercare pattern di iniezione:
```bash
grep "\[INJECT\]" id_debug.log
```

Dovrebbe mostrare:
```
[INJECT] Particle #1 ID = 0x0000000000000008 (dec 8)
[INJECT] Particle #2 ID = 0x0000000000000010 (dec 16)
[INJECT] Particle #3 ID = 0x0000000000000018 (dec 24)
...
```

#### Cercare ID zero:
```bash
grep "ZERO ID" id_debug.log
```

Se appare, c'è un problema di overflow.

#### Cercare eventi di fissione:
```bash
grep "FISSION" id_debug.log
```

Verifica che:
- Parent ID sia corretto
- Child ID siano correttamente generati (Parent*8 + index)

#### Cercare finished output:
```bash
grep "\[FINISHED\]" id_debug.log
```

Confronta con gli ID iniettati.

## Checklist Diagnostica

- [ ] Gli ID vengono iniettati correttamente? (grep "\[INJECT\]")
- [ ] Gli ID attraversano physicsworker? (grep "Advancement, Id:")
- [ ] Gli ID arrivano a eventworker? (grep "Interaction:")
- [ ] Gli ID escono correttamente? (grep "\[FINISHED\]")
- [ ] Durante fissione, gli ID figli sono corretti? (grep "Child Created")
- [ ] Ci sono ID zero rilevati? (grep "ZERO ID")
- [ ] La latenza totale rispetta i ~145 cicli attesi?

## Soluzioni Alternative

Se il problema persiste nonostante le correzioni:

### Opzione A: Ridurre Moltiplicazione ID
Cambia da x8 a x2:
```vhdl
v_out.id := std_logic_vector(unsigned(v_out.id) sll 1); -- x2 invece di x8
```

### Opzione B: ID Sequenziale Globale
Usa un contatore globale invece di tree indexing:
```vhdl
signal global_id_counter : unsigned(strlength-1 downto 0) := (others => '0');
-- Ad ogni nuova particella:
v_out.id := std_logic_vector(global_id_counter);
global_id_counter <= global_id_counter + 1;
```

### Opzione C: Aumentare strlength
Se overflow è il problema, aumenta da 64 a 128 bit:
```vhdl
-- In configopenmc.vhd:
constant strlength : integer := 128;
```

## Conclusione

Il problema "particle.id = 0 durante fissione" può avere due cause:
1. **Overflow aritmetico** - Corretto con protezione overflow
2. **Visibilità/Timing** - Da verificare con tb_id_propagation.vhd

Eseguire il testbench e analizzare i log per determinare la causa esatta.
