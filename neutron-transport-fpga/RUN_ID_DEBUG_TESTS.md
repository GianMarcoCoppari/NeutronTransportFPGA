# Istruzioni per Eseguire i Test di Debug ID

Questi testbench sono stati creati per diagnosticare il problema "particle.id = 0 durante fissione".

## Testbench Disponibili

### 1. `tb_id_immediate.vhd`
**Scopo**: Verifica che gli ID siano visibili nei primi 100 cicli durante l'iniezione.
**Output Atteso**: Sequenza di ID 0x8, 0x10, 0x18, 0x20... (8, 16, 24, 32... in decimale)

### 2. `tb_id_propagation.vhd`
**Scopo**: Verifica propagazione completa degli ID attraverso tutta la pipeline.
**Output Atteso**: Confronto tra ID iniettati e ID finali, rilevamento automatico di ID=0.

## Compilazione ed Esecuzione

### Prerequisiti
- GHDL installato (o altro simulatore VHDL come ModelSim/Questa)
- Tutti i file sorgente nella directory `utils/neutron-transport-fpga`

### Opzione A: Usare GHDL

```bash
cd /home/gianmarco/openmc/utils/neutron-transport-fpga

# 1. Compilare tutti i package e componenti base
ghdl -a config/pkg/config.vhd
ghdl -a config/pkg/configcordic.vhd
ghdl -a config/pkg/configcordich.vhd
ghdl -a config/pkg/configopenmc.vhd

# 2. Compilare componenti matematici
ghdl -a math/prng/xoshiro256.vhd
ghdl -a math/divider/radix2_stagediv.vhd
ghdl -a math/divider/divr2.vhd
ghdl -a math/cordich/poscordicstageh.vhd
ghdl -a math/cordich/negcordicstageh.vhd
ghdl -a math/cordich/cordich.vhd
ghdl -a math/cordich/customln.vhd
ghdl -a math/cordich/customsqrt.vhd
ghdl -a math/cordicc/cordicstagec.vhd
ghdl -a math/cordicc/reduceangle.vhd
ghdl -a math/cordicc/cordicc.vhd
ghdl -a math/cordicc/sincos.vhd
ghdl -a math/search/binarysearch.vhd
ghdl -a math/interp/lspline.vhd

# 3. Compilare ROM/memoria
ghdl -a config/memory/xs_rom_small.vhd
ghdl -a config/memory/xs.vhd
ghdl -a config/memory/fission_spectrum_rom.vhd

# 4. Compilare moduli fisica
ghdl -a reactor/physics/absorption.vhd
ghdl -a reactor/physics/scattering.vhd
ghdl -a reactor/physics/scattering_realistic.vhd
ghdl -a reactor/physics/fission.vhd
ghdl -a reactor/physics/energy_sample_fission.vhd
ghdl -a reactor/physics/energy_loss_scatter.vhd

# 5. Compilare worker
ghdl -a reactor/xs_lookup.vhd
ghdl -a reactor/materiallookup.vhd
ghdl -a reactor/physicsworker.vhd
ghdl -a reactor/advance/calc_dist_geometry.vhd
ghdl -a reactor/advance/calc_dist_physics.vhd
ghdl -a reactor/advance/advanceworker.vhd
ghdl -a reactor/geometryworker.vhd
ghdl -a reactor/eventworker.vhd

# 6. Compilare pipeline e scheduler
ghdl -a reactor/transportpl.vhd
ghdl -a fifo/fifo.vhd
ghdl -a fifo/scheduler.vhd

# 7. Compilare testbench
ghdl -a test/testreactor/tb_id_immediate.vhd
ghdl -a test/testreactor/tb_id_propagation.vhd

# 8. Elaborare (creare eseguibile)
ghdl -e tb_id_immediate
ghdl -e tb_id_propagation

# 9. Eseguire i test

echo "==================================================="
echo "TEST 1: Verifica ID nei primi 100 cicli"
echo "==================================================="
ghdl -r tb_id_immediate --stop-time=50us > tb_id_immediate.log 2>&1
echo "Output salvato in: tb_id_immediate.log"
echo ""

echo "==================================================="
echo "TEST 2: Verifica propagazione completa ID"
echo "==================================================="
ghdl -r tb_id_propagation --stop-time=200us > tb_id_propagation.log 2>&1
echo "Output salvato in: tb_id_propagation.log"
echo ""

# 10. Analizzare i risultati
echo "==================================================="
echo "ANALISI RISULTATI"
echo "==================================================="

echo "--- Test 1: ID Immediati (primi 100 cicli) ---"
echo "Cercando pattern di iniezione..."
grep "Inject ID" tb_id_immediate.log | head -20
echo ""

echo "--- Test 2: Propagazione ID ---"
echo "ID Iniettati:"
grep "\[INJECT\]" tb_id_propagation.log | head -10
echo ""
echo "ID Finiti:"
grep "\[FINISHED\]" tb_id_propagation.log | head -10
echo ""
echo "Errori ID Zero:"
grep "ZERO ID" tb_id_propagation.log || echo "Nessun errore ID zero rilevato"
echo ""

echo "==================================================="
echo "Per vedere tutti i dettagli:"
echo "  cat tb_id_immediate.log"
echo "  cat tb_id_propagation.log"
echo "==================================================="
```

### Opzione B: Script Bash Automatico

Salva questo contenuto in `run_id_tests.sh`:

```bash
#!/bin/bash
# Script per compilare ed eseguire i test di debug ID

set -e  # Exit on error

echo "Compilazione componenti VHDL..."

# Function to compile with error handling
compile_vhd() {
    echo "  Compiling: $1"
    ghdl -a "$1" || { echo "ERROR compiling $1"; exit 1; }
}

# Packages
compile_vhd "config/pkg/config.vhd"
compile_vhd "config/pkg/configcordic.vhd"
compile_vhd "config/pkg/configcordich.vhd"
compile_vhd "config/pkg/configopenmc.vhd"

# Math components (ordine importante per dipendenze)
compile_vhd "math/prng/xoshiro256.vhd"
compile_vhd "math/divider/radix2_stagediv.vhd"
compile_vhd "math/divider/divr2.vhd"
compile_vhd "math/cordich/poscordicstageh.vhd"
compile_vhd "math/cordich/negcordicstageh.vhd"
compile_vhd "math/cordich/cordich.vhd"
compile_vhd "math/cordich/customln.vhd"
compile_vhd "math/cordich/customsqrt.vhd"
compile_vhd "math/cordicc/cordicstagec.vhd"
compile_vhd "math/cordicc/reduceangle.vhd"
compile_vhd "math/cordicc/cordicc.vhd"
compile_vhd "math/cordicc/sincos.vhd"
compile_vhd "math/search/binarysearch.vhd"
compile_vhd "math/interp/lspline.vhd"

# Memory/ROM
compile_vhd "config/memory/xs_rom_small.vhd"
compile_vhd "config/memory/xs.vhd"
compile_vhd "config/memory/fission_spectrum_rom.vhd"

# Physics modules
compile_vhd "reactor/physics/absorption.vhd"
compile_vhd "reactor/physics/scattering.vhd"
compile_vhd "reactor/physics/scattering_realistic.vhd"
compile_vhd "reactor/physics/fission.vhd"
compile_vhd "reactor/physics/energy_sample_fission.vhd"
compile_vhd "reactor/physics/energy_loss_scatter.vhd"

# Workers
compile_vhd "reactor/xs_lookup.vhd"
compile_vhd "reactor/materiallookup.vhd"
compile_vhd "reactor/physicsworker.vhd"
compile_vhd "reactor/advance/calc_dist_geometry.vhd"
compile_vhd "reactor/advance/calc_dist_physics.vhd"
compile_vhd "reactor/advance/advanceworker.vhd"
compile_vhd "reactor/geometryworker.vhd"
compile_vhd "reactor/eventworker.vhd"

# Pipeline & Scheduler
compile_vhd "reactor/transportpl.vhd"
compile_vhd "fifo/fifo.vhd"
compile_vhd "fifo/scheduler.vhd"

# Testbenches
compile_vhd "test/testreactor/tb_id_immediate.vhd"
compile_vhd "test/testreactor/tb_id_propagation.vhd"

echo "Elaborazione testbench..."
ghdl -e tb_id_immediate
ghdl -e tb_id_propagation

echo "Esecuzione test..."
ghdl -r tb_id_immediate --stop-time=50us > tb_id_immediate.log 2>&1
ghdl -r tb_id_propagation --stop-time=200us > tb_id_propagation.log 2>&1

echo "Analisi risultati..."
echo "========================"
echo "TEST 1 - ID Immediati:"
grep "Inject ID" tb_id_immediate.log | head -10
echo ""
echo "TEST 2 - Propagazione:"
grep -E "\[INJECT\]|\[FINISHED\]|ZERO ID" tb_id_propagation.log | head -20

echo ""
echo "Log completi in: tb_id_immediate.log e tb_id_propagation.log"
```

Rendi eseguibile e lancia:
```bash
chmod +x run_id_tests.sh
./run_id_tests.sh
```

## Interpretazione Risultati

### Cosa Cercare nei Log

#### tb_id_immediate.log:
```
Ciclo 1: Inject ID=0x0000000000000008 (8 dec)
Ciclo 2: Inject ID=0x0000000000000010 (16 dec)
Ciclo 3: Inject ID=0x0000000000000018 (24 dec)
...
```

✅ **CORRETTO**: Se vedi la sequenza hex 8, 10, 18, 20, 28, 30...
❌ **PROBLEMA**: Se vedi tutti zeri o sequenze diverse

#### tb_id_propagation.log:
```
[INJECT] Particle #1 ID = 0x0000000000000008 (dec 8)
...
[FINISHED] Particle #1 ID = 0x0000000000000008 (dec 8)
```

✅ **CORRETTO**: ID iniettati = ID finiti (possono essere in ordine diverso)
❌ **PROBLEMA**: Se appare "ERROR: ZERO ID DETECTED" o ID non corrispondono

### Soluzioni Basate sui Risultati

| Risultato | Causa | Soluzione |
|-----------|-------|-----------|
| ID corretti in tb_id_immediate, ma zero in fissione | Overflow durante shift | Già corretto in eventworker.vhd |
| ID sempre zero da subito | Problema inizializzazione | Verificare EMPTYPARTICLE non sovrascriva ID |
| ID corretti primi cicli, poi spariscono | Problema pipeline | Aggiungere monitor intermedi |
| ID in decimale diversi da attesi | Confusione hex/dec | Verificare formato output |

## Troubleshooting Compilazione

Se GHDL non è disponibile, usare il simulatore disponibile:
- **ModelSim**: `vcom` invece di `ghdl -a`, `vsim` invece di `ghdl -r`
- **Vivado**: Crea progetto e aggiungi tutti i file
- **XSIM**: `xvhdl` per compilare, `xelab`+`xsim` per simulare

## Contatto e Support

Per problemi di compilazione o interpretazione risultati, fornire:
1. Errori di compilazione completi
2. Prime 50 righe di entrambi i log
3. Output di `grep "ZERO ID" tb_id_propagation.log`
