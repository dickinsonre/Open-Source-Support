# Fixes for 0005 - Import Export of Data Tables

Hardened `fix_*.rb` versions of every Ruby script in this folder. The originals
are preserved unchanged. The fixes apply a consistent template:

- `# frozen_string_literal: true` pragma.
- Header comment with purpose, inputs, outputs, type (UI/EX), hardening notes.
- `begin / rescue => e / ensure` around the main logic.
- Validation of `WSApplication`, `current_network`, prompts not cancelled,
  source files / directories exist via `File.exist?` / `Dir.exist?`,
  selections non-empty when used.
- File I/O via `File.open(...) do |f| ... end` and
  `CSV.open(...) do |csv| ... end` so handles always close.
- `transaction_begin` paired with `transaction_rollback` in the rescue branch.
- Nil-safety (`&.`, `next if obj.nil?`).
- Timestamped progress logging via a small `log` helper.

For the very large per-table CSV exporters (`export_*_to_csv.rb`,
`all_for_one_and_one_for_all.rb`, `hw_sw_all_table_reader.rb`,
`ex;port_*_to_csv.rb`, `hw_parameters.rb`, `sw_parameters.rb`), the fix
files are hardened wrappers that pre-validate the environment then delegate
to the original via `Kernel#load`, preserving 100% of the original behavior
while adding the safety wrapper.

## fix_EX_script_ICM Binary Results Export.rb

- **Purpose**: Pure-Ruby parser for the ICM binary results format (no
  WSApplication dependency).  Provides ICMBinaryReader + helper classes and
  a CLI for listing tables/attributes/objects and dumping results.
- **Hardening**: validates input file exists, closes file via ensure block,
  per-action rescue.
- **How to run**: `ruby "fix_EX_script_ICM Binary Results Export.rb" file.bin T`

## fix_IE-DashboardExport.rb

- **Purpose**: Update and export an InfoAsset Manager Dashboard to HTML.
- **Hardening**: validates DB open, model object found, output dir exists.
- **How to run**: `iexchange ... "fix_IE-DashboardExport.rb"` (edit DB_URL,
  DASH_PATH, OUT_PATH constants first).

## fix_IE-Snapshot-Bulk-Import.rb

- **Purpose**: Bulk-import all .isfc/.isf snapshots in a directory into a
  Collection Network and commit.
- **Hardening**: per-file rescue, only commits on success, source dir check.
- **How to run**: edit DB_URL, NETWORK_ID, SOURCE_DIR; run via Exchange.

## fix_IE-befdss_export.rb

- **Purpose**: Run `befdss_export` on a Collection Network to XML.
- **Hardening**: ensures output and log directories exist.
- **How to run**: edit constants; run via Exchange.

## fix_IE-befdss_import_cctv-BulkImport.rb

- **Purpose**: Bulk-import every BEFDSS XML in SOURCE_DIR via
  `befdss_import_cctv` with a per-file log.
- **Hardening**: per-file rescue keeps the run going.
- **How to run**: edit constants; run via Exchange.

## fix_IE-befdss_import_cctv.rb

- **Purpose**: Import a single BEFDSS CCTV XML file.
- **Hardening**: validates input file exists.
- **How to run**: edit constants; run via Exchange.

## fix_IE-befdss_import_manhole_surveys.rb

- **Purpose**: Import a BEFDSS manhole surveys XML file.
- **Hardening**: validates input file exists.
- **How to run**: edit constants; run via Exchange.

## fix_IE-csv_changes.rb

- **Purpose**: Generate CSV diff between two commits of a Collection Network.
- **Hardening**: ensures output dir exists.
- **How to run**: edit DB_URL, NETWORK_ID, COMMIT_FROM/TO; run via Exchange.

## fix_IE-snapshot_export_ex.rb

- **Purpose**: Export a snapshot (.isfc) for a Collection Network.
- **Hardening**: ensures output dir exists.
- **How to run**: edit constants; run via Exchange.

## fix_UI-CSV_export-selection.rb

- **Purpose**: Build a `cams_cctv_survey` selection and export to CSV.
- **Hardening**: ensures output dir exists.
- **How to run**: open a network, run via UI.

## fix_UI-CSV_export.rb

- **Purpose**: Export the entire current network to CSV (fixes the missing
  comma in the original arg list).
- **Hardening**: validates current_network and ensures output dir exists.
- **How to run**: open a network, run via UI.

## fix_UI-ExportChoiceListValues.rb

- **Purpose**: Export choice-list codes/descriptions for a field to CSV.
- **Hardening**: nil-safety on choices/descriptions; CSV.open block.
- **How to run**: open a network, run via UI.

## fix_UI-ExportPipeArrayCSV.rb

- **Purpose**: Export point_array of selected `cams_pipe` rows to CSV.
- **Hardening**: validates non-empty selection; CSV.open block.
- **How to run**: select pipes, run via UI.

## fix_UI-Snapshot-Bulk-Import-Filename.rb

- **Purpose**: Import every `*survey*.isfc` under a directory tree.
- **Hardening**: per-file rescue.
- **How to run**: open a network, run via UI.

## fix_UI-Snapshot-Bulk-Import.rb

- **Purpose**: Import every `.isfc/.isf` under a directory tree.
- **Hardening**: per-file rescue.
- **How to run**: open a network, run via UI.

## fix_UI-snapshot_export_ex.rb

- **Purpose**: Export selected CCTV + manhole surveys to a chosen .isfc.
- **Hardening**: validates dialog and current_network.
- **How to run**: select rows, run via UI.

## fix_UI-UpdateFromExternalCSV.rb

- **Purpose**: Read a CSV next to the script, update `cams_manhole.user_text_2`
  via a transaction.
- **Hardening**: validates CSV exists; transaction with rollback.
- **How to run**: place test.csv next to the script, run via UI.

## fix_UIIE-CSV_export.rb

- **Purpose**: Dual-mode CSV export (UI -> current network, EX -> open by ID).
- **Hardening**: validates network, ensures output dir exists.
- **How to run**: open a network in UI, or run via Exchange with NETWORK_ID set.

## fix_UI_script_ODEC Export Node and Conduit tables to CSV and MIF.rb

- **Purpose**: ODEC export of Node + Conduit to CSV and MIF using a
  configuration mapping file.
- **Hardening**: validates working dir and config file exist.
- **How to run**: ensure WORK_DIR and CFG_FILE point to your setup, run via UI.

## fix_UI_script_Output CSV of calcs based on Subcatchment Data.rb

- **Purpose**: Aggregate selected `_subcatchments` stats by system_type and
  write a single summary row to a chosen CSV.
- **Hardening**: validates dialog choice, network; File.open block.
- **How to run**: select subcatchments, run via UI, choose CSV.

## fix_all_for_one_and_one_for_all.rb

- **Purpose**: Wrapper around the generic SWMM table exporter
  (all_for_one_and_one_for_all.rb).  Pre-validates and delegates via `load`.
- **Hardening**: WSApplication / current_network checks; original existence
  check.
- **How to run**: open a network, run the fix in UI.

## fix_check_fields.rb

- **Purpose**: Diagnostic that lists `.fields` and selected methods on the
  first `sw_conduit` row.
- **Hardening**: per-call rescue; nil-safety.
- **How to run**: open a SWMM network with conduits, run via UI.

## fix_ex;port_hw_orifice_to_csv.rb

- **Purpose**: Wrapper around the hw_orifice exporter.  Note literal `;` in
  filename.  Delegates via `load`.
- **Hardening**: WSApplication and network checks.
- **How to run**: open a network with orifices selected, run via UI.

## fix_ex;port_hw_weir_to_csv.rb

- **Purpose**: Wrapper around the hw_weir exporter.  Note literal `;` in
  filename.  Delegates via `load`.
- **Hardening**: WSApplication and network checks.
- **How to run**: select weirs, run via UI.

## fix_export_hw_conduit_data_to_csv.rb

- **Purpose**: Wrapper around hw_conduit CSV exporter.
- **Hardening**: standard wrapper checks.
- **How to run**: select conduits, run via UI.

## fix_export_hw_node_data_to_csv.rb

- **Purpose**: Wrapper around hw_node CSV exporter.
- **Hardening**: standard wrapper checks.
- **How to run**: select nodes, run via UI.

## fix_export_hw_pump_to_csv.rb

- **Purpose**: Wrapper around hw_pump CSV exporter.
- **Hardening**: standard wrapper checks.
- **How to run**: select pumps, run via UI.

## fix_export_hw_subcatchments_to_csv.rb

- **Purpose**: Wrapper around hw_subcatchment CSV exporter.
- **Hardening**: standard wrapper checks.
- **How to run**: select subcatchments, run via UI.

## fix_export_sw_conduit_data_to_csv .rb

- **Purpose**: Wrapper around sw_conduit CSV exporter (note trailing space
  in filename, preserved as required).
- **Hardening**: standard wrapper checks.
- **How to run**: select sw_conduit rows, run via UI.

## fix_export_sw_node_data_to_csv.rb

- **Purpose**: Wrapper around sw_node CSV exporter.
- **Hardening**: standard wrapper checks.
- **How to run**: select sw_node rows, run via UI.

## fix_export_sw_orifice_to_csv.rb

- **Purpose**: Wrapper around sw_orifice CSV exporter.
- **Hardening**: standard wrapper checks.
- **How to run**: select sw_orifice rows, run via UI.

## fix_export_sw_pump_to_csv.rb

- **Purpose**: Wrapper around sw_pump CSV exporter.
- **Hardening**: standard wrapper checks.
- **How to run**: select sw_pump rows, run via UI.

## fix_export_sw_subcatchments_to_csv.rb

- **Purpose**: Wrapper around sw_subcatchment CSV exporter.
- **Hardening**: standard wrapper checks.
- **How to run**: select sw_subcatchment rows, run via UI.

## fix_export_sw_weir_to_csv.rb

- **Purpose**: Wrapper around sw_weir CSV exporter.
- **Hardening**: standard wrapper checks.
- **How to run**: select sw_weir rows, run via UI.

## fix_hw_UI-GIS_export.rb

- **Purpose**: Export hw_node/conduit/subcatchment to SHP via GIS_export.
- **Hardening**: validates folder picked and ensures it exists.
- **How to run**: open InfoWorks network, run via UI, pick folder.

## fix_hw_parameters.rb

- **Purpose**: Reference file enumerating hw_* tables.  Shim verifies
  presence of the original.
- **Hardening**: file existence and readability checks.
- **How to run**: usually loaded indirectly by the all-table reader; running
  this fix directly just confirms the file is present.

## fix_hw_simulation_parameters.rb

- **Purpose**: Diagnostic for parameter-table access patterns.
- **Hardening**: per-call rescue, nil-safety.
- **How to run**: open an ICM network, run via UI.

## fix_hw_sw_all_table_reader.rb

- **Purpose**: Wrapper around the combined hw/sw table reader/exporter.
- **Hardening**: pre-checks parameter files; delegates via `load`.
- **How to run**: open an ICM network, run via UI.

## fix_sw_UI-GIS_export.rb

- **Purpose**: Export sw_node/conduit/subcatchment to SHP via GIS_export.
- **Hardening**: validates current_network and ensures OUT_DIR exists.
- **How to run**: open an ICM SWMM network, run via UI.

## fix_sw_parameters.rb

- **Purpose**: Reference file enumerating sw_* tables.  Shim verifies
  presence of the original.
- **Hardening**: file existence and readability checks.
- **How to run**: usually loaded indirectly; running this fix directly just
  confirms the file is present.
