# Folder 0011: Get results from all timesteps in the IWR File - Fixes Summary

## Overview
This folder contains 8 Ruby scripts for extracting and reporting time-series results from all timesteps in ICM InfoWorks .iwr simulation files.

## Files Processed

### 1. fix_hw_UI_script Get results from all timesteps for Links All Params.rb
**Original:** `hw_UI_script Get results from all timesteps for Links All Params.rb`
**Purpose:** Export all result parameters from selected conduits/links across all timesteps
**Hardening Applied:**
- Added `frozen_string_literal: true`
- Full begin/rescue/ensure error handling
- Validates network and timesteps
- Checks row object exists before processing
- Safe handling of missing result fields
- Nil-safety checks on results array

**How to Run:**
```ruby
# Select one or more conduits in network
# Run from InfoWorks ICM UI Script menu
# Outputs: Console log with parameters for each link at each timestep
# Includes: depth, flow, velocity, surcharge state, etc.
```

### 2. fix_hw_UI_script Get results from all timesteps for Links, US Flow DS Flow.rb
**Original:** `hw_UI_script Get results from all timesteps for Links, US Flow DS Flow.rb`
**Purpose:** Extract upstream and downstream flow results for selected links across all timesteps
**Hardening Applied:**
- Added `frozen_string_literal: true`
- Complete error handling
- Result count validation
- Safe numeric conversion

**How to Run:**
```ruby
# Select conduits/links
# Run from UI Script menu
# Displays: US Flow and DS Flow at each timestep
```

### 3. fix_hw_UI_script Get results from all timesteps for Subcatchments All Params.rb
**Original:** `hw_UI_script Get results from all timesteps for Subcatchments All Params.rb`
**Purpose:** Extract all runoff/catchment parameters across all timesteps
**Hardening Applied:**
- Validated object and field existence
- Safe handling of missing subcatchment objects
- Result count verification

**How to Run:**
```ruby
# Select subcatchments in network
# Run from UI Script menu
# Outputs: Rainfall, runoff, infiltration, depth results per timestep
```

### 4. fix_hw_UI_script_ Get results from all timesteps for Manholes All Params.rb
**Original:** `hw_UI_script_ Get results from all timesteps for Manholes All Params.rb`
**Purpose:** Extract all manhole/node parameters across all timesteps
**Hardening Applied:**
- Network and results validation
- Nil-safe field access
- Error recovery on missing fields

**How to Run:**
```ruby
# Select nodes/manholes
# Run from UI Script menu
# Outputs: Depth, inflow, volume, surcharge at each timestep
```

### 5. fix_hw_UI_script  Get results from all timesteps for Manholes QNODE.rb
**Original:** `hw_UI_script  Get results from all timesteps for Manholes QNODE.rb`
**Purpose:** Extract inflow (QNODE) results for selected nodes
**Hardening Applied:**
- Timestep count validation
- Safe result array handling
- Error handling on missing fields

**How to Run:**
```ruby
# Select nodes
# Run from UI Script menu
# Outputs: QNODE (inflow) at each timestep
```

### 6. fix_hw_UI_script_All Node and Link URL Stats.rb
**Original:** `hw_UI_script_All Node and Link URL Stats.rb`
**Purpose:** Generate comprehensive statistics on nodes and links across all timesteps
**Hardening Applied:**
- Full error handling
- Result validation
- Safe statistics calculation

**How to Run:**
```ruby
# Run from UI Script menu
# Processes all selected nodes and links
# Outputs: Summary statistics per object
```

### 7. fix_hw_UI_script_links.rb
**Original:** `hw_UI_script_links.rb`
**Purpose:** Generic link results processor
**Hardening Applied:**
- Error handling
- Result field validation
- Nil-safety checks

### 8. fix_hw_UI_script_nodes.rb
**Original:** `hw_UI_script_nodes.rb`
**Purpose:** Generic node results processor
**Hardening Applied:**
- Network validation
- Timestep verification
- Safe field access

### SWMM Variants (3 additional scripts)
**Purpose:** SWMM-specific versions for:
- Manholes All Params
- Subcatchments All Params
- Links All Params

**Hardening:** All SWMM variants include the same error handling and validation patterns.

## Common Processing Patterns

All scripts follow this sequence:

1. **Setup:**
   ```ruby
   net = WSApplication.current_network
   ts = net.list_timesteps
   time_interval = (ts[1] - ts[0]).abs if ts.size > 1
   ```

2. **Validation:**
   ```ruby
   ro = net.row_object(table_name, object_id)
   raise "Object not found" if ro.nil?
   ```

3. **Results Extraction:**
   ```ruby
   results = ro.results(field_name)
   next unless results.size == ts.size
   ```

4. **Output:**
   ```ruby
   results.each_with_index do |value, ts_index|
     # Process value at timestep ts_index
   end
   ```

## Important Notes

- All scripts require completed simulation with results
- Timestep count must match result array size
- Result fields vary by network type (HW vs SW)
- Output is to console (stdout)
- Time interval calculated from first two timesteps
- Scripts process only selected objects

## Testing Recommendations

1. Load ICM SWMM network with results
2. Select 2-3 objects for initial testing
3. Run script and verify timestep progression
4. Confirm time interval calculation is reasonable
5. Check that all expected fields are present
6. Verify result values are within expected ranges
