# Fixes for 0006 - ICM SWMM vs ICM InfoWorks All Tables

Hardened `fix_*.rb` versions of each Ruby script in this folder. The originals
are preserved unchanged.  All fixes share the same template:
`# frozen_string_literal: true`, header comment, `begin / rescue / ensure`,
nil-safety, and timestamped progress logging via a `log` helper.

## fix_EX Run Parameters.rb

- **Purpose**: Retrieve all read/write Run fields for a given Run ID via
  `WSApplication.open` and dump them as a hash.
- **Hardening**: validates database opens, run object exists; per-field rescue
  on read; explicit error message if `run_id` not set.
- **How to run**: Edit the script and replace the `run_id = nil` placeholder
  with a real Run id, then `Database -> Run Exchange Script... ` from ICM.

## fix_ICM InfoWorks All Table Names.rb

- **Purpose**: Count rows in every known `hw_*` InfoWorks table.
- **Hardening**: per-table rescue so unknown tables (older/newer versions) do
  not abort; current_network nil-check.
- **How to run**: Open an InfoWorks ICM network, `Network -> Run Ruby Script...`.

## fix_ICM SWMM All Tables.rb

- **Purpose**: Count rows in every known `sw_*` ICM SWMM table.
- **Hardening**: per-table rescue, nil-check, timestamped log.
- **How to run**: Open an ICM SWMM network, `Network -> Run Ruby Script...`.

## fix_ICM SWMM Network Overview.rb

- **Purpose**: Aggregate stats for sw_node, sw_conduit, sw_subcatchment, plus
  counts of pumps/weirs/orifices/outlets.
- **Hardening**: nil-checks on every attribute, zero-division guards on means,
  `begin/rescue/ensure`.
- **How to run**: Open an ICM SWMM network, `Network -> Run Ruby Script...`.

## fix_compare_icm_swmm_icm_files.rb

- **Purpose**: Library helper that compares column 1 of two CSV files.
- **Hardening**: validates both files exist, tolerant to unequal row counts,
  reports diffs to stdout.
- **How to run**: `require_relative 'fix_compare_icm_swmm_icm_files'` then call
  `compare_icm_swmm_icm_files(path_a, path_b)`.

## fix_find_hw_runoff_tables.rb

- **Purpose**: From a selection on hw_runoff_surface, propagate selection to
  matching hw_land_use rows and then their hw_subcatchment rows.
- **Hardening**: requires non-empty selection, nil-safe attribute access.
- **How to run**: Select rows in hw_runoff_surface, then run via UI.

## fix_Sensor_Comparison.rb

- **Purpose**: Plot ICM model results vs measured sensor data with line and
  scatter graphs.
- **Hardening**: validates folder dialog, file existence, results presence;
  per-location rescue.
- **How to run**: Run the script in ICM, choose the sensor data folder when
  prompted.

## fix_sw_UI_Get_script_CN_BN.rb

- **Purpose**: Compute time-series sum/mean/min/max for selected sw_conduit
  rows for FLOW/DEPTH/HGL/etc, plus d/D and q/Q ratios.
- **Hardening**: skips selections without rows, nil-safe diameter/full_flow,
  per-field rescue.
- **How to run**: Select conduits, ensure simulation results loaded, run.

## fix_sw_hw_UI_Set_Script_CN_BN.rb

- **Purpose**: Copy capacity/gradient from background hw_conduit rows onto
  current sw_conduit rows as user_number_9 / user_number_10.
- **Hardening**: validates both networks, transaction with rollback.
- **How to run**: Open SWMM network as current, InfoWorks network as
  background, then run.

## fix_sw_UI_Script_additional_dwf_nodes_icm_swmm.rb

- **Purpose**: Stats on sw_node base_flow and additional_dwf baselines.
- **Hardening**: nil-safe iteration; defensive `print_stats` helper.
- **How to run**: Open ICM SWMM network, run via UI.

## fix_sw_UI_Script_Calculate statistics for baseline data.rb

- **Purpose**: Stats (MGD and GPM) on additional_dwf baselines per sw_node.
- **Hardening**: nil-safe iteration, empty-data guard.
- **How to run**: Open ICM SWMM network, run via UI.
