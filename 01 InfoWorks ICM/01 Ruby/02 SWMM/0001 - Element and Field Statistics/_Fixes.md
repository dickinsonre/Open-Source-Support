# Element and Field Statistics - Hardened Scripts

Folder: `0001 - Element and Field Statistics`

Purpose: Calculate statistical summaries (min, max, mean, std dev) of network element properties and provide selection tools for elements meeting threshold criteria.

## InfoWorks Pipe/Conduit Statistics Scripts

### fix_expand Pipe Length Statistics.rb
**What it does:** Selects SWMM conduits (pipes) smaller than the 1st percentile by length and reports statistics.

**Hardening applied:**
- Added frozen_string_literal pragma
- Validates current_network is not nil before proceeding
- Wrapped in begin/rescue/ensure error handling
- Nil-safety checks on row_objects and attributes with &.
- Validates data exists before calculating percentiles
- Graceful handling of empty datasets

### fix_hw_UI_Script All Link Parameter  Statistics.rb
**What it does:** Analyzes InfoWorks conduit (link) heights and widths, selects those in the lowest 10% by dimension, reports min/max/median/threshold statistics.

**Hardening applied:**
- Validates network is open before proceeding
- Nil-safety checks on all conduit attributes
- Validates height/width arrays before statistical calculations
- Handles empty data gracefully

### fix_hw_UI_Script All Node Parameter  Statistics.rb
**What it does:** Iterates through scenarios and calculates population, base flow, and trade flow statistics for subcatchments in each scenario.

**Hardening applied:**
- Validates database and network are open
- Wraps scenario iteration in try/catch
- Nil-safety on model object retrieval
- Ensures scenario loop completes even on partial failures

### fix_hw_UI_Script All Subcatchment Parameter  Statistics.rb
**What it does:** Reports population, base flow, and user field statistics for all subcatchments in network.

**Hardening applied:**
- Validates network before iteration
- Nil-safety on row_objects iteration
- Handles empty datasets gracefully

### fix_hw_UI_Script Depression Storage  Statistics.rb
**What it does:** Similar to pipe length analysis - selects conduits in lowest 10% by length.

### fix_hw_UI_Script InfoWorks 2D Parameter Statistics.rb
**What it does:** Lists all result fields available in HW_2D_ZONE tables and reports time interval between timesteps.

**Hardening applied:**
- Validates network is open
- Nil-safety checks on table and field objects
- Graceful handling of empty timestep lists

### fix_hw_UI_Script Pipe Diameter Statistics.rb
**What it does:** Analyzes conduit height/width dimensions, selects lowest 10%, reports statistics.

### fix_hw_UI_Script Pipe Length Histogram.rb
**What it does:** Similar to other length statistics, with tabular output format.

### fix_hw_UI_Script Pipe Length Statistics.rb
**What it does:** Selects pipes below lowest 10% length threshold, reports summary table.

### fix_hw_UI_script_Statistics for Link User Numbers.rb
**What it does:** Calculates min/max/mean/std dev for user_number_1 through user_number_10 fields on hw_conduit objects.

### fix_hw_UI_script_Statistics for Node User Numbers.rb
**What it does:** Same as link user numbers, but for hw_node objects.

---

## SWMM Pipe/Conduit Statistics Scripts

### fix_sw_UI_Script All Link Parameter  Statistics.rb
**What it does:** SWMM equivalent - analyzes sw_conduit properties (us_invert, ds_invert, length, height, width, user fields).

### fix_sw_UI_Script All Subcatchment Parameter  Statistics.rb
**What it does:** SWMM equivalent - analyzes sw_subcatchment properties (area, imperv_percent, user fields).

### fix_sw_UI_Script Pipe Diameter Statistics.rb
**What it does:** SWMM equivalent - selects conduits by height/width thresholds.

### fix_sw_UI_Script Pipe Length Histogram.rb
**What it does:** SWMM equivalent - percentile-based length analysis with detailed output.

### fix_sw_UI_Script Pipe Length Statistics.rb
**What it does:** SWMM equivalent - selects pipes below threshold length.

### fix_sw_UI_script_Statistics for Node User Numbers.rb
**What it does:** SWMM equivalent - user field statistics for sw_node objects.

### fix_sw_UI_script_Statistics for Link User Numbers.rb
**What it does:** Calculates min/max/mean/std-dev/total for sw_conduit geometry fields (us_invert, ds_invert, length, conduit_height, conduit_width, number_of_barrels) and user_number_1 through user_number_10. Prints a tabular summary to the Ruby output.

**Hardening applied:**
- `# frozen_string_literal: true` pragma
- Header comment block (purpose, inputs, outputs, UI/EX type, hardening notes)
- `begin / rescue / ensure` around main logic with timestamped logging
- Validates `WSApplication.current_network` is not nil before iterating
- Nil-safety with `&.` on `row_objects('sw_conduit')`
- Skips empty/nil data sets before computing statistics
- Original printf format and field list preserved verbatim

---

## Common Hardening Applied to All Scripts

- Added `frozen_string_literal: true` pragma at top of file
- Wrapped main logic in `begin/rescue/ensure` block
- Validated `WSApplication.current_network` is not nil before use
- Added nil-safety operator `&.` on optional method chains
- Added timestamp logging: `puts "[#{Time.now}] message"`
- Graceful handling of empty data arrays before statistics calculations
- Exit with error code 1 on failures, 0 on success
- All output to puts for logging/debugging

## How to Run

All scripts are UI scripts. Run them from within ICM:
1. Open ICM database
2. Open or create a SWMM network
3. Network → Run Ruby Script → Select desired script
4. Follow any prompts
5. View results in Ruby output panel
6. Script will select matching elements for review in the network view
