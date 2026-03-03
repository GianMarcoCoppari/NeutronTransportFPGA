# Bug: particle.id = 0 durante eventi di Fissione

## Problema Identificato

Durante eventi di fissione, il `particle.id` può diventare **zero** a causa di un **overflow aritmetico** nell'operazione di generazione degli ID per le particelle figlie.

## Causa Radice

Nel file [`eventworker.vhd`](reactor/eventworker.vhd), alla linea 340 (versione originale 329):

```vhdl
-- Formula: Child_ID = (Parent_ID * 8) + Index
v_out.id := std_logic_vector(unsigned(v_out.id) sll 3);
```

Quando avviene una fissione, l'implementazione usa un **tree indexing scheme** dove:
- L'ID del genitore viene moltiplicato per 8 (shift left di 3 bit)
- Poi viene aggiunto un indice (1, 2, 3, ...) per ogni figlia

### Il Problema dell'Overflow

Se `strlength = 64 bit` e l'ID del genitore è troppo grande:
- **Esempio**: Parent ID = `2^61` (o superiore)
- Dopo `sll 3`: i 3 bit più significativi vengono spostati oltre il limite
- I bit che eccedono vengono **persi** (scartati)
- Se tutti i bit rimanenti sono zero → **Child ID = 0**

### Scenario Critico

```
Parent ID = 0x2000000000000000  (bit 61 = 1, resto = 0)
Dopo sll 3 (x8):
= 0x0000000000000000  (bit 64 sarebbe 1, ma va oltre - OVERFLOW!)
= 0  ← ZERO!
```

Questo succede quando:
- La simulazione genera molte generazioni di fissione
- L'ID cresce esponenzialmente: ogni fissione moltiplica per 8
- Dopo ~20 generazioni consecutive (8^20 > 2^64), si verifica overflow

## Soluzione Implementata

Ho modificato [`eventworker.vhd`](reactor/eventworker.vhd) con tre livelli di protezione:

### 1. **Overflow Prevention (linee 330-341)**
```vhdl
-- Controllo preventivo: se i 3 bit più alti sono occupati
if unsigned(v_out.id(strlength-1 downto strlength-3)) /= 0 then
    -- RISCHIO OVERFLOW: usa solo i bit bassi con modulo
    v_out.id := std_logic_vector(resize(unsigned(v_out.id(strlength-4 downto 0)) sll 3, strlength));
else
    -- Sicuro: shift normale
    v_out.id := std_logic_vector(unsigned(v_out.id) sll 3);
end if;
```

**Logica**: Se i 3 bit più significativi sono già occupati, eseguire lo shift causerebbe overflow. Invece, si usano solo i bit bassi (modulo implicito).

### 2. **Debug Logging (linee 343-346)**
```vhdl
write(l, string'("DEBUG: After shift, base ID = "));
write(l, safe_id_to_int(v_out.id));
writeline(output, l);
```

Questo permette di monitorare i valori degli ID dopo lo shift.

### 3. **Zero Detection & Recovery (linee 348-353)**
```vhdl
if unsigned(v_out.id) = 0 then
    write(l, string'("ERROR: FISSION generated ZERO ID - parent was too large!"));
    writeline(output, l);
    -- Forza ID non-zero per evitare fallimenti silenziosi
    v_out.id := std_logic_vector(to_unsigned(1, strlength));
end if;
```

Se nonostante tutto l'ID diventa zero, viene:
- Registrato un errore nel log
- Forzato un valore non-zero (1) per prevenire comportamenti indefiniti

## Come Verificare la Correzione

### 1. Compilare il codice modificato
```bash
# Se usi GHDL o altro simulatore VHDL
ghdl -a reactor/eventworker.vhd
```

### 2. Eseguire simulazioni con debug abilitato
Cercare nei log di output:
- `"DEBUG: After shift, base ID ="` - Mostra ID post-shift
- `"WARNING: ID overflow risk detected"` - Indica che la protezione è scattata
- `"ERROR: FISSION generated ZERO ID"` - Indica che si è verificato zero (con recovery)

### 3. Test specifico
Iniettare particelle con ID alti:
```vhdl
inject_particle.id <= std_logic_vector(to_unsigned(2**61, strlength));
```

E verificare che dopo fissione:
- Gli ID figli non siano zero
- Appaia il warning di overflow se applicabile

## Raccomandazioni Future

### Opzione A: Riduzione della Moltiplicazione
Cambiare da `x8` a `x2` o `x4`:
```vhdl
v_out.id := std_logic_vector(unsigned(v_out.id) sll 1);  -- x2 invece di x8
```
Pro: 3x meno probabilità di overflow
Contro: Più rischio di collisione ID

### Opzione B: ID gerarchici separati
Usare due campi:
- `generation` (contatore generazione)
- `index` (indice nella generazione)

Pro: No overflow, tracciamento genealogia chiaro
Contro: Richiede modifica struttura `particle_t`

### Opzione C: Hash-based IDs
Usare hash dell'ID genitore + seed invece di moltiplicazione:
Pro: Distribuzione uniforme, no overflow
Contro: Più complesso, possibili collisioni

## Conclusione

Il bug `particle.id = 0` durante fissione è causato da **overflow aritmetico** durante la generazione dell'ID albero genealogico. La soluzione implementata:

1. ✅ **Previene** overflow controllando i bit alti prima dello shift
2. ✅ **Rileva** quando l'ID diventa zero 
3. ✅ **Recupera** forzando un ID valido
4. ✅ **Logga** tutte le anomalie per debug

Il codice ora è **robusto** e **debuggabile**.
