# FPGA Neutron Transport for Gen-IV Reactors

Experimental VHDL implementation of a Monte Carlo neutron transport engine, targeting FPGA acceleration for Generation IV reactor physics simulations.

## Project Overview

This project aims to implement a fully pipelined, hardware-accelerated Monte Carlo particle transport simulation. Unlike conventional CPU-based simulations (e.g., OpenMC, MCNP), this architecture exploits the massive parallelism of FPGAs to handle particle tracking, geometry navigation, and interaction physics concurrently.

**Target Context:** Generation IV Nuclear Reactors (Advanced Physics requiring high-fidelity simulation).

## Current Status: Development Pre-Alpha (v0.2)

⚠️ **Note:** This project is actively under development.

The current version (`v0.2-realistic-scattering`) implements the structural backbone of the transport engine with **realistic isotropic scattering**. Cross sections and energy dependence still use simplified models.

### Implemented Features
*   **Pipeline Architecture:** Full loop including Scheduler, Geometry (Ray Tracing), and Event kernels.
*   **Particle Tracking:** 64-bit ID system with recursive "Tree Indexing" to track fission genealogy (Parent -> Children) without collisions.
*   **Geometry Engine:** Fixed-point (Q16.48) arithmetic for precise ray tracing in 3D Cartesian geometry.
*   **Banking System:** Recursive handling of secondary particles (fission products) via a feedback loop.
*   **Logging:** Detailed event tracing (`track2.log`) and genealogy reporting.

### Recently Implemented (v0.2-realistic-scattering)
*   **✅ Realistic Scattering:** Isotropic scattering using spherical coordinates (μ, φ) with dual CORDIC pipeline
    - Algorithm: Sample cos(θ) ∈ [-1,1] and φ ∈ [0,2π], compute (sin(θ)cos(φ), sin(θ)sin(φ), μ)
    - Components: CORDIC Hyperbolic (sqrt) + CORDIC Circular (sin/cos)
    - Latency: ~100 cycles (fully pipelined)
    - Throughput: 1 direction/cycle after pipeline fill
    - Validation: Unit vector normalization guaranteed

### Remaining Limitations (Physics)
*   **Cross Sections:** Constant values are used instead of energy-dependent data lookups.
*   **Energy:** Particle energy is carried but does not yet drive physics parameters.
*   **Anisotropic Scattering:** Currently isotropic in lab frame; needs rotation for CM→Lab transformation.

## Repository Structure

*   `reactor/`: Core logic (Geometry, Physics Worker, Event handling).
    - `physics/`: Scattering, absorption, fission kernels
        - `scattering_realistic.vhd` ✨ NEW: Realistic isotropic scattering
        - `scattering.vhd`: Legacy mock implementation
*   `fifo/`: Scheduler and Queue management.
*   `math/`: Custom arithmetic units (Divisori, CORDIC, RNG Xoshiro256).
    - `cordich/customsqrt.vhd` ✨ NEW: CORDIC hyperbolic square root
*   `config/`: Configuration packages and type definitions.
*   `run/`: Simulation scripts and logs (GHDL via `compile.sh`).
    - `test_scattering.sh` ✨ NEW: Standalone scattering test

## Next Steps

### High Priority
*   ✅ ~~Realistic Scattering~~ → **COMPLETED** (see `docs/INTEGRATION_GUIDE.md`)
*   Integration of energy-dependent Cross Section lookup (ROM/RAM).
*   Tallying system (flux, reaction rates, k-eff)

### Medium Priority
*   Anisotropic scattering with rotation (CM→Lab frame transformation)
*   Ray Tracing improvements (multi-region CSG)
*   Physical probability distribution sampling
*   Integrated Data Preprocessing

### Testing & Validation
*   Run `./run/test_scattering.sh` to validate realistic scattering
*   Compare results with OpenMC software on benchmark cases
*   Performance analysis on FPGA hardware

## 📚 Documentation

*   **[`docs/INTEGRATION_GUIDE.md`](docs/INTEGRATION_GUIDE.md)** - Complete integration guide for realistic scattering
*   **[`docs/SCATTERING_SUMMARY.md`](docs/SCATTERING_SUMMARY.md)** - Executive summary of scattering implementation
*   **[`docs/SCATTERING_FLOWCHART.txt`](docs/SCATTERING_FLOWCHART.txt)** - ASCII flowchart and resource estimates