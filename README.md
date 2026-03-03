# FPGA-Accelerated Monte Carlo Neutron Transport

Fully pipelined VHDL-2008 implementation of a Monte Carlo neutron transport engine targeting FPGA acceleration, with energy-dependent nuclear data from real cross-section libraries and physics-grade fixed-point arithmetic.

Developed as part of a Master's thesis on hardware acceleration of reactor physics simulations for Generation IV nuclear reactor design.

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Numeric Representation](#numeric-representation-q1648-fixed-point)
4. [Pipeline Modules and Latencies](#pipeline-modules-and-latencies)
5. [Nuclear Data Preprocessing](#nuclear-data-preprocessing)
6. [Physics Models](#physics-models)
7. [Repository Structure](#repository-structure)
8. [Compilation and Simulation](#compilation-and-simulation)
9. [Simulation Results](#simulation-results)
10. [Limitations and Future Work](#limitations-and-future-work)
11. [References](#references)

---

## Overview

Traditional Monte Carlo neutron transport codes (OpenMC, MCNP, Serpent) run on CPUs and are inherently sequential per-particle. This project implements the full particle transport loop — geometry ray-tracing, energy-dependent cross-section lookup, collision physics, and fission banking — as a **deeply pipelined VHDL hardware design**, exploiting the deterministic latency and massive parallelism of FPGAs.

### Key Features

| Feature | Description |
|---|---|
| **Full transport loop** | Scheduler → Physics (d_collision) → Geometry (ray-trace) → Event decision → Feedback |
| **Energy-dependent cross sections** | ROM tables from ENDF nuclear data (B-10, U-235, U-238), binary search + linear interpolation |
| **Realistic isotropic scattering** | Spherical sampling via dual CORDIC pipeline (hyperbolic √ + circular sin/cos) |
| **Fission banking** | Recursive secondary particle emission with tree-indexed genealogy tracking |
| **Fixed-point arithmetic** | Q16.48 format (64-bit), no floating-point units required |
| **Fully pipelined** | All major datapaths unrolled; throughput = 1 result/clock after pipeline fill |
| **Particle lifecycle management** | 256-entry FIFO with priority feedback arbiter and backpressure |

### Project Statistics

- **68 VHDL source files** (49 design + 19 testbenches)
- **~6,000 lines** of handwritten VHDL logic (excluding auto-generated ROM data)
- **9 C++ preprocessing files** for nuclear data → VHDL ROM generation
- **34 compilation units** in the main build flow

---

## Architecture

The transport engine is structured as a **closed-loop pipeline** managed by a central scheduler:

```
                    ┌──────────────────────────────────────────────────────────┐
                    │                     SCHEDULER                            │
                    │  ┌──────┐    ┌──────────┐    ┌──────────────────────┐   │
    Inject ────────►│  │ FIFO │───►│ Dispatch │───►│   TRANSPORT PIPELINE  │   │
                    │  │ 256  │    │   FSM    │    │                      │   │
                    │  │entry │◄───┤ Arbiter  │    │  ┌───────────────┐   │   │
                    │  └──────┘    │(feedback │    │  │ physicsworker │   │   │
                    │              │priority) │    │  │  d_coll calc  │   │   │
                    │              └──────────┘    │  │  (~79 cycles) │   │   │
                    │                              │  └──────┬────────┘   │   │
                    │                              │         ▼            │   │
                    │   Feedback ◄─────────────────│  ┌──────────────┐   │   │
                    │  (scatter/                    │  │geometryworker│   │   │
                    │   fission)                    │  │  ray-trace   │   │   │
                    │                              │  │ (64 cycles)  │   │   │
                    │                              │  └──────┬────────┘   │   │
    Output ◄────────│                              │         ▼            │   │
   (absorbed/       │                              │  ┌──────────────┐   │   │
    leaked)         │                              │  │ eventworker  │   │   │
                    │                              │  │  FSM + prob  │   │   │
                    │                              │  │ (~80 cycles) │   │   │
                    │                              │  └──────────────┘   │   │
                    │                              └──────────────────────┘   │
                    └──────────────────────────────────────────────────────────┘
```

### Data Flow

1. **Scheduler** dispatches a particle from the FIFO into the transport pipeline
2. **Physics Worker** computes distance-to-collision: `d_coll = −ln(ξ) / Σ_total(E)` using PRNG → CORDIC ln → ROM interpolation
3. **Geometry Worker** computes distance-to-boundary via 3 parallel fixed-point dividers, then compares with `d_coll` to determine **COLLISION** vs **SURFACE_CROSSING**
4. **Event Worker** handles the outcome:
   - *Surface crossing*: kill particle (vacuum boundary) or reflect
   - *Collision*: query `prob_lookup` for energy-dependent P_abs(E), P_fiss(E); sample interaction type; dispatch to absorption/fission/scattering kernel
5. **Feedback**: surviving particles (scattered or fission daughters) re-enter the FIFO with absolute priority over new injections

---

## Numeric Representation: Q16.48 Fixed-Point

All physical quantities (positions, directions, energies, cross sections) use a **64-bit signed fixed-point** format:

```
 Bit 63    Bits 62–48      Bits 47–0
┌──────┬───────────────┬──────────────────────────────────────────┐
│ Sign │  Integer (15b) │         Fractional (48 bits)             │
└──────┴───────────────┴──────────────────────────────────────────┘
```

| Value | Hex Representation | Notes |
|---|---|---|
| 1.0 | `0x0001_0000_0000_0000` | 2⁴⁸ |
| 500.0 mm | `0x01F4_0000_0000_0000` | Reactor half-edge |
| 0.02 mm⁻¹ | `0x0000_051E_B851_EB85` | Cross section |
| 0.946 (94.6%) | `0x0000_F1ED_7C89_9A24` | P_absorption at thermal |

This format avoids floating-point hardware entirely while providing ~14.3 decimal digits of fractional precision, sufficient for Monte Carlo convergence.

---

## Pipeline Modules and Latencies

Every arithmetic unit is **fully unrolled and pipelined** — no resource sharing or iterative loops. This guarantees deterministic latency and 1-result-per-clock throughput after the pipeline is filled.

### Latency Summary

| Module | File | Latency (cycles) | Architecture |
|---|---|---|---|
| **Xoshiro256\*\* PRNG** | `math/prng/xoshiro256.vhd` | 2 | Scrambler pipeline |
| **Binary Search** | `math/search/binarysearch.vhd` | 7 | log₂(64) + 1 stages |
| **Circular CORDIC (sin/cos)** | `math/cordicc/sincos.vhd` | 49 | 48 rotation stages + input reg |
| **Hyperbolic CORDIC** | `math/cordich/cordich.vhd` | 57 | 5 neg + 52 pos stages |
| **Custom ln(x)** | `math/cordich/customln.vhd` | 58 | CORDIC vectoring + prescale |
| **Custom √x** | `math/cordich/customsqrt.vhd` | 58 | CORDIC vectoring + prescale |
| **Radix-2 Divider** | `math/divider/divr2.vhd` | 64 | 64 restoring-division stages |
| **Linear Spline Interpolation** | `math/interp/lspline.vhd` | 69 | Input + Δ calc + divr2(64) + mul + add + output |
| **XS Lookup (1/Σ_total)** | `reactor/xs_lookup.vhd` | ~77 | binarysearch(7) + fetch(1) + lspline(69) |
| **Prob Lookup (P_abs, P_fiss)** | `reactor/prob_lookup.vhd` | ~77 | Shared search + 2× parallel lspline |
| **Physics Worker** | `reactor/physicsworker.vhd` | ~79 | PRNG → ln(58) ∥ xs_lookup(77) → multiply(2) |
| **Geometry Worker** | `reactor/geometryworker.vhd` | 64 | 3× parallel divr2 + min + compare |
| **Scattering (realistic)** | `reactor/physics/scattering_realistic.vhd` | ~100 | √(1−μ²)(58) ∥ sincos(φ)(49) → multiply |
| **Absorption** | `reactor/physics/absorption.vhd` | 1 | Combinatorial kill |
| **Fission** | `reactor/physics/fission.vhd` | 1 | ν decision + daughter setup |
| **Energy Loss (elastic)** | `reactor/physics/energy_loss_scatter.vhd` | 6 | α sampling + multiply |

### Composite Latencies

| Path | Latency | Description |
|---|---|---|
| **Transport pipeline** (`transportpl`) | **~143 cycles** | physicsworker(79) + geometryworker(64) |
| **Event worker** (collision path) | **~80 cycles** | prob_lookup(77) + kernel(1) + decision(2) |
| **Full particle iteration** (no scattering) | **~225 cycles** | Transport + event + scheduler overhead |
| **Full iteration with scattering** | **~325 cycles** | + scattering_realistic(100) |

### Pipeline Alignment Strategy

The `physicsworker` internally aligns two parallel computation paths using a **delay line (shift register)**: the `-ln(ξ)` result (58 cycles) is delayed by 19 additional cycles to synchronize with the `xs_lookup` result (77 cycles) before the final multiplication.

Similarly, in `prob_lookup`, a single shared `binarysearch` feeds **two parallel `lspline` instances** (absorption and fission channels), ensuring both probabilities are ready simultaneously.

---

## Nuclear Data Preprocessing

The C++ preprocessor (`preprocessing/`) reads ENDF-format cross-section data files and generates synthesizable VHDL ROM packages.

### Preprocessing Pipeline

```
  B-10.dat (934 pts) ─────┐
  U-235.dat (76,514 pts) ──┼──► Union Energy Grid ──► Downsample (stride=200) ──► 64-entry ROMs
  U-238.dat (157,739 pts) ─┘         (merge)              (select points)
```

### Generated ROM Arrays (`xs_rom_small.vhd`)

| ROM Array | Content | Usage |
|---|---|---|
| `ROM_ENERGY` | Energy grid nodes (MeV) | Binary search key |
| `ROM_SIGMA_TOTAL` | Σ_total(E) macroscopic | Validation |
| `ROM_INV_SIGMA_TOTAL` | 1/Σ_total(E) precomputed | Physics worker (d_collision) |
| `ROM_SIGMA_SCATTER` | Σ_scatter(E) | Reference |
| `ROM_SIGMA_FISSION` | Σ_fission(E) | Reference |
| `ROM_NU_SIGMA_FISSION` | ν·Σ_fission(E) | Future: k-eff tallying |
| `ROM_PROB_ABSORPTION` | P_abs(E) = 1 − Σ_s/Σ_t − Σ_f/Σ_t | Event worker |
| `ROM_PROB_FISSION` | P_fiss(E) = Σ_f/Σ_t | Event worker |
| `ROM_PROB_SCATTER` | P_scat(E) = Σ_s/Σ_t | Reference |

All values are pre-converted to Q16.48 format. The 64-entry grid spans the full energy range with sufficient resolution for the interpolation scheme.

### Preprocessing Source Files

| File | Purpose |
|---|---|
| `main.cpp` | Entry point, orchestration |
| `xsec_preprocess.cpp` | Cross-section file parsing |
| `uniongrid.cpp` | Multi-nuclide energy grid union |
| `rom.cpp` | VHDL ROM array generation with probability pre-computation |
| `lspline.cpp` | Interpolation verification |
| `physics.cpp` | Physics constant computation |
| `fission_spectrum.cpp` | Watt fission spectrum sampling |
| `generate_fission_rom.cpp` | Fission spectrum ROM generation |
| `memoryinit.cpp` | Memory initialization file output |

---

## Physics Models

### Distance to Collision

Sampled from an exponential distribution:

$$d_{\text{coll}} = -\frac{\ln(\xi)}{\Sigma_{\text{total}}(E)}$$

where ξ is a uniform random number from the Xoshiro256\*\* PRNG. The implementation computes this as:

$$d_{\text{coll}} = (-\ln(\xi)) \times \frac{1}{\Sigma_{\text{total}}(E)}$$

where $1/\Sigma_{\text{total}}(E)$ is fetched from ROM via binary search + linear interpolation.

### Geometry: Distance to Boundary

For an axis-aligned cubic reactor (1 m edge, ±500 mm):

$$d_{\text{axis}} = \frac{|B - P_{\text{axis}}|}{|\Omega_{\text{axis}}|}$$

$$d_{\text{boundary}} = \min(d_x, d_y, d_z)$$

Three **parallel** radix-2 dividers compute all three axis distances simultaneously (64 cycles).

### Interaction Type Selection

At each collision, the particle energy E determines the interaction probabilities from ROM:

$$P_{\text{abs}}(E), \quad P_{\text{fiss}}(E), \quad P_{\text{scat}}(E) = 1 - P_{\text{abs}}(E) - P_{\text{fiss}}(E)$$

A uniform random sample ξ selects:
- **Absorption**: ξ < P_abs(E) → particle killed
- **Fission**: P_abs(E) ≤ ξ < P_abs(E) + P_fiss(E) → emit ν daughters (ν ∈ {2,3}, ⟨ν⟩ ≈ 2.43)
- **Scattering**: ξ ≥ P_abs(E) + P_fiss(E) → new direction sampled isotropically

### Isotropic Scattering

New direction sampled uniformly on the unit sphere:

$$\mu = \cos\theta \sim \mathcal{U}[-1, 1], \quad \phi \sim \mathcal{U}[0, 2\pi]$$

$$\Omega' = \left(\sqrt{1-\mu^2}\cos\phi, \; \sqrt{1-\mu^2}\sin\phi, \; \mu\right)$$

Implemented using:
1. `customsqrt` (CORDIC hyperbolic): $\sqrt{1-\mu^2}$ — 58 cycles
2. `sincos` (CORDIC circular): $\sin\phi$, $\cos\phi$ — 49 cycles
3. Final multiplications — 2 cycles

Total: **~100 cycles**, fully pipelined (1 new direction per clock after fill).

### Elastic Energy Loss

$$E' = E \cdot \alpha, \quad \alpha = \alpha_{\min} + \xi(1 - \alpha_{\min})$$

where $\alpha_{\min} = \left(\frac{A-1}{A+1}\right)^2$ for target mass number A (default: U-235, $\alpha_{\min}$ ≈ 0.983).

### Fission Multiplicity

$$\nu = \begin{cases} 2 & \text{with probability 57\%} \\ 3 & \text{with probability 43\%} \end{cases} \quad \Rightarrow \quad \langle\nu\rangle \approx 2.43$$

Consistent with U-235 thermal fission data. Daughter IDs use **tree indexing**: `Child_ID = Parent_ID × 8 + index`, enabling collision-free genealogy tracking across all fission generations.

---

## Repository Structure

```
neutron-transport-fpga/
├── config/
│   ├── pkg/
│   │   ├── config.vhd              # Q16.48 format, global constants
│   │   ├── configopenmc.vhd        # Particle record, material/nuclide types
│   │   ├── configcordic.vhd        # Circular CORDIC constants (48-entry atan LUT)
│   │   └── configcordich.vhd       # Hyperbolic CORDIC constants (57-entry atanh LUT)
│   └── memory/
│       └── xs_rom_small.vhd        # 9 ROM arrays (64 entries × 64 bits), auto-generated
│
├── math/
│   ├── adder/
│   │   ├── cla4.vhd                # 4-bit carry-lookahead adder
│   │   └── ccla16.vhd              # 16-bit cascaded CLA
│   ├── divider/
│   │   ├── radix2_stagediv.vhd     # Single radix-2 division stage
│   │   └── divr2.vhd               # 64-stage pipelined divider
│   ├── cordich/                     # Hyperbolic CORDIC (ln, sqrt, sinh, cosh)
│   │   ├── cordich.vhd             # 57-stage pipeline (5 neg + 52 pos iterations)
│   │   ├── poscordicstageh.vhd     # Positive iteration stage
│   │   ├── negcordicstageh.vhd     # Negative iteration stage
│   │   ├── customln.vhd            # -ln(x) via CORDIC vectoring
│   │   └── customsqrt.vhd          # √x via CORDIC vectoring
│   ├── cordicc/                     # Circular CORDIC (sin, cos)
│   │   ├── sincos.vhd              # 49-stage sin/cos pipeline
│   │   ├── cordicstagec.vhd        # Circular rotation stage
│   │   └── reduceangle.vhd         # Angle reduction to [0, 2π]
│   ├── prng/
│   │   └── xoshiro256.vhd          # Xoshiro256** PRNG (64-bit, 2-cycle latency)
│   ├── search/
│   │   └── binarysearch.vhd        # Pipelined binary search (log₂(N)+1 cycles)
│   └── interp/
│       └── lspline.vhd             # Linear spline interpolation (69 cycles)
│
├── reactor/
│   ├── transportpl.vhd             # Transport pipeline top-level (physics → geometry)
│   ├── physicsworker.vhd           # d_collision = -ln(ξ)/Σ_t(E), ~79 cycles
│   ├── geometryworker.vhd          # 3D ray-trace, 3× parallel dividers, 64 cycles
│   ├── eventworker.vhd             # 5-state FSM: prob lookup → interaction decision
│   ├── xs_lookup.vhd               # Energy → 1/Σ_total ROM interpolation, ~77 cycles
│   ├── prob_lookup.vhd             # Energy → P_abs, P_fiss ROM interpolation, ~77 cycles
│   ├── materiallookup.vhd          # Cell → material mapping
│   └── physics/
│       ├── absorption.vhd           # Particle kill (1 cycle)
│       ├── fission.vhd              # ν sampling + daughter emission (1 cycle)
│       ├── scattering_realistic.vhd # Isotropic scattering via CORDIC (~100 cycles)
│       ├── scattering.vhd           # Legacy simplified scattering
│       └── energy_loss_scatter.vhd  # Elastic energy loss (6 cycles)
│
├── fifo/
│   ├── fifo.vhd                    # 256-entry synchronous circular buffer
│   └── scheduler.vhd               # Particle lifecycle: inject → pipeline → feedback/output
│
├── test/
│   └── testloop/
│       └── tb_scheduler.vhd        # Integration testbench (single + burst injection)
│
├── preprocessing/                   # C++ nuclear data → VHDL ROM converter
│   └── src/
│       ├── main.cpp                 # Entry point
│       ├── rom.cpp                  # VHDL ROM generation + probability computation
│       ├── xsec_preprocess.cpp      # Cross-section file parser
│       ├── uniongrid.cpp            # Multi-nuclide energy grid union
│       └── ...                      # (9 files total)
│
└── run/
    ├── compile.sh                   # GHDL build + simulate script
    └── outputlog/
        └── simulation.log           # Simulation event log
```

---

## Compilation and Simulation

### Prerequisites

- **GHDL** (ghdl-gcc backend, VHDL-2008 support)
- **GTKWave** (optional, for VCD waveform viewing)
- **g++** with C++17 support (for preprocessing only)

### Quick Start

```bash
cd neutron-transport-fpga/run/
rm -f *.o *.cf    # Clean stale build artifacts
bash compile.sh
```

The script compiles **34 VHDL files** in dependency order, elaborates `tb_scheduler`, and runs a 100 μs simulation producing:
- `outputlog/simulation.log` — textual event trace
- `scheduler_trace.vcd` — full waveform dump (viewable in GTKWave)

### Compilation Order (Dependency Chain)

The build follows a strict bottom-up dependency order:

```
1. Config packages     config → configcordic → configcordich → configcordicc → configopenmc → xs_rom_small
2. Adders              cla4 → ccla16
3. Divider             radix2_stagediv → divr2
4. CORDIC hyperbolic   negcordicstageh → poscordicstageh → cordich → customln → customsqrt
5. CORDIC circular     reduceangle → cordicstagec → sincos
6. Utilities           xoshiro256 → binarysearch → lspline
7. Physics kernels     absorption → scattering → energy_loss_scatter → scattering_realistic → fission
8. Reactor             materiallookup → calc_dist_geometry → xs_lookup → physicsworker →
                       geometryworker → prob_lookup → eventworker → transportpl
9. Infrastructure      fifo → scheduler
10. Testbench          tb_scheduler
```

### Preprocessing (ROM Generation)

To regenerate the cross-section ROM from nuclear data:

```bash
cd preprocessing/
g++ -O3 -std=c++17 src/*.cpp -o preprocess
./preprocess    # Reads *.dat files, outputs xs_rom_small.vhd
```

Input data files: `B-10.dat`, `U-235.dat`, `U-238.dat` (ENDF pointwise cross sections).

---

## Simulation Results

### Testbench: `tb_scheduler`

The integration testbench runs at **100 MHz** (10 ns clock) and performs two tests:

**Test 1 — Single Particle**
- Injects particle ID=8 into cell 1 (FUEL), with unit direction along X and thermal energy
- Particle undergoes transport → collision → prob_lookup → **ABSORPTION** (P_abs ≈ 94.6% at thermal)
- Pipeline round-trip: ~225 cycles (~2.25 μs at 100 MHz)

**Test 2 — Burst of 20 Particles**
- Injects 20 particles (IDs: 16, 24, ..., 168) using handshake protocol (`scheduler_ready` backpressure)
- Scheduler processes particles sequentially (1 in-flight at a time via `pending_box = 0`)
- Each particle follows the full lifecycle: transport → event → absorption/scatter/fission → output/feedback

### Verified Outputs

```
Advancement, Id: 8  dist: 000015E9BF697414
Interaction: ABSORPTION, Id: 8
[OUT] Particle Finished ID:8 Reason: DYING

Advancement, Id: 24 dist: 00001381A960CA6D
Interaction: ABSORPTION, Id: 24
[OUT] Particle Finished ID:24 Reason: DYING
```

- **Particle IDs**: correctly propagated through the entire pipeline (confirmed via debug traces)
- **prob_abs**: `0x0000F1ED7C899A24` ≈ **94.6%** — physically consistent with thermal neutron absorption in a B-10 / U-235 / U-238 mixture
- **Distance values**: sampled from exponential distribution, correctly scaled by 1/Σ_total(E)

### Performance Characteristics (GHDL Simulation)

| Metric | Value |
|---|---|
| Simulated clock frequency | 100 MHz (10 ns period) |
| Cycles per particle iteration | ~225–325 (depending on interaction) |
| Simulated time per particle | ~3 μs |
| GHDL wall-clock per simulated μs | ~1.5 s |
| GHDL wall-clock per particle | ~4.5 s |
| 100-particle simulation | ~7 min |
| 1000-particle simulation | ~75 min |

> **Note**: These are GHDL *interpretation* speeds. On FPGA hardware at 100+ MHz, each particle iteration would complete in ~2–3 μs of real time, enabling millions of particles per second.

---

## Limitations and Future Work

### Current Limitations

- **Geometry**: Single axis-aligned cube (1 m edge); no CSG Boolean regions or multi-cell support
- **Anisotropic scattering**: Isotropic in lab frame only; center-of-mass → lab frame transformation not yet implemented
- **Tallying**: No flux, reaction rate, or k-eigenvalue accumulation
- **Throughput**: `pending_box = 0` constraint serializes particles; future work can pipeline multiple particles with proper hazard management
- **Boundary conditions**: Vacuum (kill) only; no reflective or periodic boundaries

### Planned Extensions

| Priority | Feature | Description |
|---|---|---|
| High | **Tallying system** | Flux maps, reaction rates, k-eff eigenvalue estimation |
| High | **Multi-particle pipelining** | Remove serialization constraint; pipeline N particles simultaneously |
| Medium | **Anisotropic scattering** | CM→Lab rotation matrix for angular distributions |
| Medium | **Multi-region geometry** | CSG-based cell definitions with surface-crossing logic |
| Medium | **Reflective boundaries** | Mirror boundary conditions for symmetry exploitation |
| Low | **FPGA synthesis** | Target Xilinx/Intel FPGA; resource utilization and timing analysis |
| Low | **OpenMC validation** | Side-by-side comparison on standard benchmarks (Jezebel, Godiva) |

---

## References

- **OpenMC**: [https://docs.openmc.org](https://docs.openmc.org) — Reference Monte Carlo neutron transport software
- **ENDF/B-VIII.0**: Evaluated Nuclear Data File — Source of cross-section data
- **VHDL-2008**: IEEE Standard 1076-2008
- **CORDIC Algorithm**: Volder (1959), "The CORDIC Trigonometric Computing Technique"
- **Xoshiro256\*\***: Blackman & Vigna (2018), "Scrambled Linear Pseudorandom Number Generators"
- **GHDL**: [https://ghdl.github.io/ghdl/](https://ghdl.github.io/ghdl/) — Open-source VHDL simulator