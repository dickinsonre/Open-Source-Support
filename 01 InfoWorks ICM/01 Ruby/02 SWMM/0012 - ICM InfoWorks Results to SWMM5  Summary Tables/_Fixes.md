# Folder 0012: ICM InfoWorks Results to SWMM5 Summary Tables - Fixes Summary

## Overview
This folder contains 6 Ruby scripts that generate SWMM5-compatible summary tables from ICM InfoWorks simulation results. These mimic the standard SWMM5 report format for easy comparison and validation.

## Files Processed

### 1. fix_hw_UI_script._swmm5_link_flows_summary_table.rb
**Original:** `hw_UI_script._swmm5_link_flows_summary_table.rb`
**Purpose:** Generate SWMM5-style Link Flow Summary table from ICM results
**Hardening Applied:**
- Added `frozen_string_literal: true`
- Complete begin/rescue/ensure error handling
- Network and results validation
- CSV file handling with block form
- Safe numeric conversions and formatting
- Progress logging for multiple links

**Output Format (SWMM5-compatible):**
```
Link                     Flow     Depth    Velocity   Capacity
                        (cmd)      (m)      (m/s)     (%)
Link1                    12.34     0.56      1.23      45.2
```

**How to Run:**
```ruby
# Run from InfoWorks ICM UI Script menu
# Automatically processes all conduits with results
# Outputs CSV to configured location
# Statistics: Min, Max, Mean flow per link
```

### 2. fix_hw_UI_script_swmm5_node_depths_summary_table.rb
**Original:** `hw_UI_script_swmm5_node_depths_summary_table.rb`
**Purpose:** Generate SWMM5-style Node Depth Summary table from ICM results
**Hardening Applied:**
- Complete error handling
- Validates node objects exist
- Result field verification
- Safe statistics calculations
- CSV generation with resource cleanup

**Output Format (SWMM5-compatible):**
```
Node              Max Depth    Time of Max    Min Depth    Avg Depth
                    (m)         (hours)         (m)          (m)
Node1               2.34         3.5            0.01         0.45
```

**How to Run:**
```ruby
# Run from UI Script menu
# Processes all nodes with depth results
# Generates depth statistics table
# Exports to CSV format
```

### 3. fix_hw_UI_script_swmm5_node_inflows_summary_table.rb
**Original:** `hw_UI_script_swmm5_node_inflows_summary_table.rb`
**Purpose:** Generate SWMM5-style Node Inflow Summary table
**Hardening Applied:**
- Network validation
- Inflow field existence checking
- Safe numeric accumulation
- Error recovery on missing fields

**Output Format (SWMM5-compatible):**
```
Node              Total Inflow    Max Inflow    Time of Max
                  (Million gal)      (cmd)       (hours)
Node1             123.45          45.67          2.5
```

### 4. fix_hw_UI_script_swmm5_node_surcharge_summary_table.rb
**Original:** `hw_UI_script_swmm5_node_surcharge_summary_table.rb`
**Purpose:** Generate SWMM5-style Node Surcharge Summary table
**Hardening Applied:**
- Surcharge field validation
- Safe boolean state handling
- Duration calculation checks
- Error handling on missing surcharge data

**Output Format (SWMM5-compatible):**
```
Node          Surcharge        Max Depth     Duration
             (type)             (m)          (hours)
Node1        Full Surcharge     2.45          0.75
```

### 5. fix_hw_UI_script_swmm5_conduit_surcharge_summary_table.rb
**Original:** `hw_UI_script_swmm5_conduit_surcharge_summary_table.rb`
**Purpose:** Generate SWMM5-style Conduit Surcharge Summary table
**Hardening Applied:**
- Complete error handling
- Surcharge state validation
- Duration tracking
- Safe division on time calculations

**Output Format (SWMM5-compatible):**
```
Conduit           Surcharge State    Duration    Max Depth
                                    (hours)       (m)
Link1            Surcharged         1.25         0.34
```

### 6. fix_hw_UI_script_swmm5_runoff_summary_table.rb
**Original:** `hw_UI_script_swmm5_runoff_summary_table.rb`
**Purpose:** Generate SWMM5-style Runoff Summary table from subcatchment results
**Hardening Applied:**
- Subcatchment object validation
- Runoff field existence checking
- Safe rainfall accumulation
- Statistics calculation with nil guards

**Output Format (SWMM5-compatible):**
```
Subcatchment      Total Runoff    Peak Runoff    Rainfall     Runoff Coeff
                 (Million gal)      (cms)        (inches)
SC1              45.67            12.34          2.5          0.65
```

## Common SWMM5 Patterns

All summary table scripts:

1. **Read ICM Results:**
   ```ruby
   cn = WSApplication.current_network
   objects = cn.row_objects(table_name)
   results = obj.results(field_name)
   ```

2. **Calculate SWMM5 Statistics:**
   ```ruby
   max_val = results.max
   max_time = timesteps[results.index(max_val)]
   mean_val = results.sum / results.count
   ```

3. **Format as CSV:**
   ```ruby
   CSV.open(filename, 'w') do |csv|
     csv << headers
     csv << row_data
   end
   ```

4. **Handle Missing Data:**
   ```ruby
   next if results.nil? || results.empty?
   value = result.to_f
   next unless value.finite?
   ```

## SWMM5 Compatibility

These scripts are designed to produce output compatible with:
- SWMM5 standard report format
- Spreadsheet import (Excel, Calc)
- Hydraulic modeling comparison
- Model calibration documentation

**Important Note:** ICM result units should match SWMM5 expectations:
- Depth: meters (m)
- Flow: m³/s or cms
- Time: hours
- Volume: m³ or Million Gallons

## Testing Recommendations

1. Run a test simulation in ICM with known results
2. Generate SWMM5 summary tables using these scripts
3. Compare output format with actual SWMM5 reports
4. Verify statistics calculations:
   - Max values and timing
   - Total volumes (sum check)
   - Mean values
5. Check CSV imports to Excel without errors
6. Validate that surcharge detection is correct

## Output Files

All scripts generate:
- **Location:** User's configured export folder
- **Format:** CSV (comma-separated values)
- **Naming:** `SWMM5_[TableType]_[Timestamp].csv`
- **Headers:** SWMM5-compatible column names
- **Encoding:** UTF-8

## Notes

- Requires completed ICM SWMM simulation
- Results must be loaded in network
- All selected objects are processed
- Statistics calculated from available timesteps
- Compatible with SWMM5 EPA version
