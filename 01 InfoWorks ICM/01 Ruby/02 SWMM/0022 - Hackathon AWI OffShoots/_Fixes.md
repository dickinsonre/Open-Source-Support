# 0022 - Hackathon AWI OffShoots - Hardened Wrapper Notes

This folder contains large multi-scenario InfoSWMM/SWMM5 importer scripts.
Each `fix_<original>.rb` is a thin, hardened wrapper around its original
script. Wrappers preserve original behavior exactly via `Kernel#load`,
adding the following hardening layer:

- `# frozen_string_literal: true` pragma
- File-level header (purpose, inputs, outputs, UI/EX, hardening notes)
- `begin / rescue StandardError / rescue Interrupt / rescue SystemExit / ensure`
- Pre-flight validation (original script presence, ENV config sanity)
- Timestamped wrapper-level progress logging (stderr for EX, stdout for UI)
- UI wrappers verify `WSApplication` is defined and surface error dialogs
- EX wrappers verify `ICM_IMPORT_CONFIG` (when set) points to a real file
- `SystemExit` is propagated so the original's `exit` codes are preserved

Behavior of the underlying logic - imports, deduplication, cleanup, scenario
merging, run setup, validation, statistics - is preserved unchanged.

## fix_InfoSWMM_Import_Exchange_Folder.rb
Wraps the multi-scenario InfoSWMM Exchange importer (deduplicates Rainfall
Events / Inflows, builds merged scenario network, sets up SWMM runs).

## fix_InfoSWMM_Import_Exchange_Folder_Enhanced.rb
Wraps the enhanced importer that also accepts H2OMapSWMM `.hsm` / `.HSDB`
inputs and emits comprehensive DBF field statistics.

## fix_InfoSWMM_Import_UI_Folder.rb
Wraps the UI counterpart that prompts the user, writes the YAML config,
and launches the Exchange worker.

## fix_InfoSWMM_Import_UI_Folder_Enhanced.rb
Wraps the enhanced UI script (DBFReader, full statistics support).

## fix_SWMM5_Import_Exchange_Annotated.rb
Wraps the heavily commented "novice friendly" SWMM5 Exchange worker.

## fix_SWMM5_Import_ICM_InfoWorks_with_Cleanup_Exchange.rb
Wraps the Version-3 refactored Exchange worker (Logger, validation,
performance metrics, sw_label cleanup).

## fix_SWMM5_Import_ICM_InfoWorks_with_Cleanup_UI.rb
Wraps the Version-3.1 UI script that uses the robust 4-element prompt
format and improved batch summary reporting.

## fix_SWMM5_Import_ICM_SWMM_with_Cleanup_Exchange.rb
Wraps the Version-2 SWMM-network Exchange worker (single/batch/recursive,
aggregate stats, summary file).

## fix_SWMM5_Import_ICM_SWMM_with_Cleanup_UI.rb
Wraps the Version-2 SWMM-network UI script (Single/Batch/Recursive modes,
summary-file based reporting).

## fix_SWMM5_Import_UI_Annotated.rb
Wraps the heavily commented novice-friendly UI script.
