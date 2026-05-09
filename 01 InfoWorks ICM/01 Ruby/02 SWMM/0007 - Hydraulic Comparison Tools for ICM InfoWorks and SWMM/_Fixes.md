# Folder 0007 Hardening Report: Hydraulic Comparison Tools

## Overview
7 math-heavy UI scripts for InfoWorks ICM hydraulic comparisons (HEC-22 inlets, Kutter's formula, shear stress/tau).

## Per-Script Summary

### fix_hw_UI_script_compare_icm_headloss.rb
- **Purpose**: HEC-22 inlet efficiency comparison for selected nodes
- **Inputs**: Network, selected nodes, result fields (DEPNOD, FloodDepth, GLLYFLOW, GTTRSPRD, INLETEFF, OVDEPNOD)
- **Outputs**: Tabular console output with HEC-22 vs ICM inlet spread/efficiency
- **Hardening**:
  - Frozen string literals
  - begin/rescue/ensure wrapper with fatal error logging
  - Network nil-check
  - Timestep validation (size >= 2)
  - nil-safe field results handling
  - Zero-guard on depnod_value division (icm_spreadsheet = 0 if depnod == 0)
  - opening_length validation before division
  - Indexed field access for robustness
  - Progress logging with timestamps

### fix_UI_script Tau or Shear Stress non QM Calculations.rb
- **Purpose**: Calculate tau (shear stress) statistics in USA (62.4 lb/ft³) or SI (998.34 N/m³) units
- **Inputs**: Selected conduits, unit system prompt (Boolean pair)
- **Outputs**: Mean/Max/Min tau values for upstream and downstream per conduit
- **Hardening**:
  - Frozen strings
  - begin/rescue/ensure with error logging
  - Network nil-check
  - User prompt validation (checked for cancellation)
  - Unit system validation (at least one selected)
  - Timestep size validation
  - nil-safe depth/gradient results handling
  - Empty tau array validation before statistics
  - Rescue on to_f conversions (defaults to 0.0)
  - Progress count and timestamp logging

### fix_hw_UI_scripta Compare ICM Headloss.rb
- **Purpose**: HEC-22 inlet efficiency comparison (duplicate of first with same hardening)
- **Inputs**: Network, selected nodes, result fields
- **Outputs**: Tabular console HEC-22 vs ICM inlet comparison
- **Hardening**: Identical to fix_hw_UI_script_compare_icm_headloss.rb

### fix_hw_UI_script_compare_icm_inlets_hec22_inlets.rb
- **Purpose**: HEC-22 inlet efficiency comparison (third variant)
- **Inputs**: Network, selected nodes, result fields
- **Outputs**: Tabular console HEC-22 vs ICM inlet comparison
- **Hardening**: Identical to other HEC-22 variants

### fix_kutter_tm Kutter Sql for ICM SWMM.rb
- **Purpose**: Calculate Kutter's formula capacity for all links at full, 3/4, and 1/2 fill levels
- **Inputs**: Network links (iterate all), extract conduit_height, gradient, bottom_roughness_N
- **Outputs**: Table with Link ID, diameter, slope, Manning's N, and capacities (ICM vs Kutter's)
- **Hardening**:
  - Frozen strings
  - begin/rescue/ensure with error logging
  - Network nil-check
  - Conversion of properties to float with default fallback
  - Validation: conduit_height > 0, gradient >= 0, Manning's N > 0
  - Zero-guard on division (add 0.0001 to denominators)
  - Zero-safe Math.sqrt with epsilon guard
  - Link iteration with try/catch per link
  - Progress count and timestamp logging
  - Header printed once on first link

### fix_kutter_tm.rb
- **Purpose**: Define reusable Kutter's formula methods (coefficient, full/3/4/half capacity)
- **Inputs**: Test values (conduit_height=48in, gradient=100 ft/ft*100, Manning's N=0.013)
- **Outputs**: Console output with calculated full, 3/4, 1/2 capacity values
- **Hardening**:
  - Frozen strings
  - Method-level input validation (nil-checks, bounds)
  - Zero-guard on division (add epsilon 0.0001)
  - Zero-safe Math.sqrt with epsilon
  - begin/rescue/ensure wrapper
  - Graceful error messages with backtrace

### fix_tau_shear_stress.rb
- **Purpose**: Calculate tau statistics in USA or SI units (identical to second script)
- **Inputs**: Selected conduits, unit system prompt
- **Outputs**: Mean/Max/Min tau per conduit
- **Hardening**: Identical to fix_UI_script Tau or Shear Stress non QM Calculations.rb

## How to Run

1. **HEC-22 Inlet Scripts** (headloss, compare_icm_inlets, compare_icm_inlets_hec22_inlets):
   - Open InfoWorks ICM UI
   - Select target nodes
   - Run script via Tools > Ruby Scripts
   - Review tabular console output (DEPNOD, inlet efficiency, HEC-22 spread, eff difference)

2. **Tau/Shear Stress Scripts**:
   - Open InfoWorks ICM UI
   - Select target conduits
   - Run script
   - When prompted, choose USA Units or SI Units
   - Review console output (upstream/downstream tau mean/max/min)

3. **Kutter's Formula Scripts**:
   - kutter_tm.rb: Run standalone to test coefficient/capacity calculation
   - kutter_tm Kutter Sql for ICM SWMM.rb: Run to iterate all links and display Kutter vs ICM capacity

## Common Issues & Troubleshooting

- **"Network is nil"**: Ensure a network is open in InfoWorks ICM
- **"Insufficient timesteps"**: Ensure results are available (run simulation first)
- **"No unit system selected"**: When prompted, select USA or SI Units
- **"Missing depth/gradient results"**: Verify simulation includes required fields (HYDGRAD, us_depth, ds_depth)
- **Division by zero**: Scripts guard against zero diameter/slope/depth; invalid conduits are skipped with warnings

## Original Issues Addressed

- Missing nil-checks on network, selected objects, results arrays
- Unguarded division (zero depnod, slope, diameter)
- No error handling on field lookups
- Missing input validation (unit system prompt, timestep count)
- No progress logging or timestamps
- Potential silent failures in result processing

