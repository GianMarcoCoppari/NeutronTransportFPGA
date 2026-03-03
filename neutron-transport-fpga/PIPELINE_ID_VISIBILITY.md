# Visibilità ID nella Pipeline - Spiegazione

## Domanda

Perché vedo l'ID solo quando `finished_valid='1'` e non durante l'evoluzione della particella nella pipeline?

## Risposta Breve

Nel [`top.vhd`](reactor/top.vhd) attuale, esponi solo `particleout` (output finale dello scheduler). Durante l'evoluzione, le particelle sono **dentro la pipeline** ma i loro ID non sono collegati a VIO/ILA!

## Architettura Pipeline

```
[Injection] → [FIFO] → [PhysicsWorker] → [GeometryWorker] → [EventWorker] → [Output]
   ^            ^            ^                  ^                  ^              ^
   |            |            |                  |                  |              |
VIO Input   nascosto!    nascosto!         nascosto!          nascosto!      VIO Output
(visible)                                                                    (visible)
```

### Flusso Dettagliato:

1. **Injection** (VIO → Scheduler):
   - ✅ `particlein.id` visibile in VIO (probe_out3)
   - Particella entra nello scheduler

2. **FIFO** (interno a scheduler.vhd):
   - ❌ `fifo_dout.id` NON esposto in top.vhd
   - Particella in coda, ID esiste ma non visibile

3. **PhysicsWorker** (~80 cicli):
   - ❌ `p_out.id` NON esposto in top.vhd
   - Particella calcola distanza collisione
   - ID propagato internamente ma non visibile

4. **GeometryWorker** (~64 cicli):
   - ❌ `particleout.id` (interno) NON esposto
   - Particella calcola distanza boundary
   - ID propagato ma non visibile

5. **EventWorker** (1-2 cicli):
   - ❌ `particle_out.id` NON esposto
   - Particella subisce evento (scatter/absorption/fission)
   - ID modificato se fissione

6. **Scheduler Output**:
   - ✅ `finished_particle.id` visibile (probe_in2)
   - Particella terminata, ID finale visibile

## Perché Non Vedi ID Durante Evoluzione

Nel file [`scheduler.vhd`](fifo/scheduler.vhd), i componenti interni sono istanziati ma i loro segnali intermedi non sono riportati come **output** dell'entity scheduler.

```vhdl
-- In scheduler.vhd (semplificato):

entity scheduler is
    port (
        inject_particle   : in  particle_t;   -- ✅ Visibile (input)
        finished_particle : out particle_t;   -- ✅ Visibile (output)
        -- MA: fifo_dout, pipe_p_out, etc. NON sono porte!
    );
end entity;

architecture rtl of scheduler is
    signal fifo_dout : particle_t;      -- ❌ Segnale INTERNO
    signal pipe_p_out : particle_t;     -- ❌ Segnale INTERNO
    signal ev_p_out : particle_t;       -- ❌ Segnale INTERNO
begin
    -- Questi segnali esistono ma non sono accessibili dall'esterno!
end architecture;
```

## Come Vedere ID Durante Evoluzione

### Opzione 1: Modificare scheduler.vhd (Aggiungere Porte Debug)

Aggiungi porte di debug allo scheduler:

```vhdl
entity scheduler is
    port (
        -- ... porte esistenti ...
        
        -- Debug: esposizione pipeline interna
        debug_fifo_id      : out std_logic_vector(strlength-1 downto 0);
        debug_physics_id   : out std_logic_vector(strlength-1 downto 0);
        debug_geometry_id  : out std_logic_vector(strlength-1 downto 0);
        debug_event_id     : out std_logic_vector(strlength-1 downto 0);
        
        debug_fifo_valid   : out std_logic;
        debug_physics_valid: out std_logic;
        debug_geometry_valid: out std_logic;
        debug_event_valid  : out std_logic
    );
end entity;
```

Poi in architecture:

```vhdl
-- Collega segnali interni alle porte debug
debug_fifo_id      <= fifo_dout.id;
debug_physics_id   <= pipe_p_out.id;
debug_geometry_id  <= (altro segnale da geometryworker);
debug_event_id     <= ev_p_out.id;

debug_fifo_valid   <= not fifo_empty;
debug_physics_valid<= pipe_done;
debug_geometry_valid<= (geometryworker validout);
debug_event_valid  <= ev_done;
```

### Opzione 2: ILA Hierarchical Probe (Vivado)

Senza modificare codice, puoi usare **ILA con probe gerarchici**.

In Vivado, quando aggiungi ILA:

1. **Synthesis** → Right-click su `instscheduler/fifo_dout` → Mark Debug
2. **Synthesis** → Right-click su `instscheduler/pipe_p_out` → Mark Debug
3. **Synthesis** → Right-click su `instscheduler/ev_p_out` → Mark Debug

Questo espone segnali interni automaticamente nell'ILA.

**Problema**: Aumenta utilizzo risorse FPGA significativamente.

### Opzione 3: Contatore Particelle in Pipeline

Aggiungi contatori per ogni stadio (più leggero):

```vhdl
-- In top.vhd, aggiungi segnali:
signal particles_in_fifo     : unsigned(7 downto 0);
signal particles_in_physics  : unsigned(7 downto 0);
signal particles_in_geometry : unsigned(7 downto 0);
signal particles_in_event    : unsigned(7 downto 0);
```

Poi esponi in VIO per vedere quante particelle ci sono in ogni stadio.

## Cosa Succede Realmente

### Scenario: Inietti 10 Particelle con ID 8, 16, 24...

**Ciclo 0-20**: Iniezione
```
FIFO:     [8, 16, 24, 32, 40, 48, 56, 64, 72, 80]
Physics:  []
Geometry: []
Event:    []
Output:   []
```

**Ciclo 100**: Pipeline si riempie
```
FIFO:     [48, 56, 64, 72, 80]  (gli altri sono usciti)
Physics:  [8, 16, 24]            (ognuno a stadio diverso)
Geometry: [...]
Event:    []
Output:   []  (nessuno ancora finito!)
```

**Ciclo 150**: Prima particella finisce
```
FIFO:     [80]
Physics:  [40, 48, 56]
Geometry: [24, 32]
Event:    [16]
Output:   [8]  ← SOLO QUESTO È VISIBILE in VIO!
```

### Nel top.vhd Attuale

```vhdl
-- Linea 175:
probe_in2 => particleout.id,  -- Vedi SOLO ID=8 in questo momento

-- NON ESPOSTO:
-- probe_inX => fifo_dout.id,      -- Vedrebbe ID=80
-- probe_inY => physics_id,        -- Vedrebbe ID=40, 48, 56 (multi!)
-- probe_inZ => geometry_id,       -- Vedrebbe ID=24, 32
```

## Soluzione Pratica

### Per Vedere "Snapshot" Pipeline

Aggiungi a scheduler.vhd porte debug minimali:

```vhdl
entity scheduler is
    port (
        -- ... esistenti ...
        
        -- Debug snapshot: ultimo ID visto in ogni stadio
        debug_last_injected_id : out std_logic_vector(strlength-1 downto 0);
        debug_last_physics_id  : out std_logic_vector(strlength-1 downto 0);
        debug_last_event_id    : out std_logic_vector(strlength-1 downto 0)
    );
end entity;
```

Con registri di cattura:

```vhdl
-- In scheduler architecture:
process(clk)
begin
    if rising_edge(clk) then
        if inject_valid = '1' then
            debug_last_injected_id <= inject_particle.id;
        end if;
        
        if pipe_done = '1' then
            debug_last_physics_id <= pipe_p_out.id;
        end if;
        
        if ev_done = '1' then
            debug_last_event_id <= ev_p_out.id;
        end if;
    end if;
end process;
```

Poi in top.vhd:

```vhdl
signal debug_inj_id, debug_phy_id, debug_evt_id : std_logic_vector(63 downto 0);

instscheduler : entity work.scheduler
    port map (
        -- ... esistenti ...
        debug_last_injected_id => debug_inj_id,
        debug_last_physics_id  => debug_phy_id,
        debug_last_event_id    => debug_evt_id
    );

-- Esponi in VIO:
probe_in17 => debug_inj_id,
probe_in18 => debug_phy_id,
probe_in19 => debug_evt_id,
```

## Conclusione

**Domanda originale**: Perché vedo ID solo a `finished_valid`?

**Risposta**: Perché nel design attuale, `particleout` (output scheduler) è l'UNICO segnale esposto in top.vhd. Gli ID esistono durante tutta l'evoluzione pipeline, ma sono segnali **interni** a scheduler.vhd e quindi non visibili in VIO/ILA.

**Soluzioni**:
1. ✅ **Modificare scheduler** per esporre segnali debug intermedi
2. ✅ **ILA hierarchical probes** (via Vivado Synthesis)
3. ✅ **Registri cattura** per ultimo ID visto per stadio (leggero)

Se vuoi vedere ID durante evoluzione, la soluzione più pulita è aggiungere porte debug allo scheduler.
