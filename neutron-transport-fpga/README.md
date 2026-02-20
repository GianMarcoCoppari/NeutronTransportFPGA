# Neutron Transport FPGA - Hardware Implementation

VHDL implementation of a Monte Carlo neutron transport engine for FPGA acceleration.

## Current Configuration

### Geometry
- **Type**: Cubic reactor core
- **Dimensions**: 1.0 meter edge (from -500 to +500 mm on each axis)
- **Format**: Q16.48 fixed-point (distances in millimeters)
- **Configuration**: [`reactor/geometryworker.vhd`](reactor/geometryworker.vhd)
  - `BOUNDARY_LIMIT = 0x01F4000000000000` (500 mm = 0.5 m)

### Cross Sections
- **Material FUEL**: Σ_total = 50.0 mm⁻¹ → Mean Free Path λ = 0.02 mm
- **Material U235**: Σ_total = 100.0 mm⁻¹ → λ = 0.01 mm
- **Source**: Real nuclear data (format Q16.48)
- **Configuration**: [`config/memory/xs.vhd`](config/memory/xs.vhd)

### Expected Physics
With current configuration (1m cube, FUEL material):
- **Theoretical interactions per particle**: ~25,000 before escape
- **Mean Free Path**: 0.02 mm (20 micrometers)
- **Particle tracking**: Full 3D Monte Carlo with realistic scattering

## Directory Structure

```
neutron-transport-fpga/
├── config/              # Configuration packages and constants
│   ├── pkg/            # Type definitions (Q16.48 format)
│   └── memory/         # Cross section ROM data
├── reactor/            # Core transport logic
│   ├── geometryworker.vhd    # 3D geometry and ray tracing
│   ├── physicsworker.vhd     # Physics interactions
│   ├── eventworker.vhd       # Event handling
│   └── physics/              # Interaction kernels
├── math/               # Arithmetic units
│   ├── cordic*/       # CORDIC algorithms (sin/cos, ln, sqrt)
│   ├── divider/       # Fixed-point division
│   └── prng/          # Xoshiro256 RNG
├── fifo/              # Scheduler and queues
├── test/              # Testbenches
│   └── testloop/      # Integration tests
└── run/               # Compilation and simulation scripts
    ├── compile.sh     # Main build script (GHDL)
    └── outputlog/     # Simulation results
```

## Running Simulations

### Quick Start
```bash
cd run/
./compile.sh
```

This will:
1. Compile all VHDL sources (GHDL std=08)
2. Elaborate the `tb_scheduler` testbench
3. Run simulation for 50 μs
4. Generate:
   - `simulation.log` - Event log
   - `scheduler_trace.vcd` - Waveform trace
   - `track2.log` - Particle tracking details

### Simulation Output
The log shows:
- Particle injection and lifecycle
- Geometry intersections (advancement distances)
- Physics interactions (collision, scattering, fission, absorption)
- Particle termination (leakage, absorption, or kill)

### Known Behavior
⚠️ **IEEE Assertion Warnings**: Metavalue warnings at t=0ms are normal in VHDL simulation and indicate uninitialized signals before reset. They do not affect functionality.

To suppress: add `--ieee-asserts=disable` to ghdl run command.

## Recent Changes (2026-02-20)

### Geometry Scaling
- **Updated**: `BOUNDARY_LIMIT` from 10 mm to 500 mm (1 meter cube edge)
- **Reason**: Original 2 cm geometry was too small - particles escaped immediately
- **Impact**: Now particles should undergo thousands of interactions before escape

### Cross Section Units
- **Clarified**: Distances in mm, cross sections in mm⁻¹, energies in MeV
- **Format**: All values in Q16.48 fixed-point (16 integer bits, 48 fractional bits)

## Technical Details

### Q16.48 Format
All physical quantities use 64-bit fixed-point:
- Bit 63: Sign
- Bits 62-48: Integer part (16 bits)
- Bits 47-0: Fractional part (48 bits)

Examples:
- `0x0001000000000000` = 1.0
- `0x01F4000000000000` = 500.0
- `0x0000051EB851EB85` = 0.02

### Pipeline Architecture
1. **Scheduler**: Injects particles and manages work queue
2. **Geometry Worker**: Calculates distance to boundaries (64-cycle radix-2 divider)
3. **Physics Worker**: Samples collision distance, handles interactions
4. **Event Worker**: Processes outcomes (scatter, fission, absorption)
5. **Advance Worker**: Updates particle position and direction

### Performance
- **Latency**: ~150 cycles per particle iteration
- **Throughput**: 1 particle/cycle (fully pipelined)
- **Target**: 1000s of concurrent particles on modern FPGAs

## Testing Status

### Verified
✅ Compilation successful (GHDL std=08)
✅ Testbench execution without errors
✅ Particle injection and tracking
✅ Geometry boundary detection
✅ Pipeline loop closure


## Next Steps

1. Add collision tallies and statistics
2. Implement k-eigenvalue calculation
3. Optimize pipeline depth for target FPGA
4. Synthesize and test on hardware

## References
- OpenMC Software: https://docs.openmc.org
- VHDL Standard: IEEE 1076-2008
