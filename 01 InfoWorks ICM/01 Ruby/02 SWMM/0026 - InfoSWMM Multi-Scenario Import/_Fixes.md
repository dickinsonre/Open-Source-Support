# InfoSWMM Multi-Scenario Import - Hardened Scripts

Folder: `0000 - InfoSWMM Multi-Scenario Import`

Purpose: Import multiple InfoSWMM scenarios from .mxd files into InfoWorks ICM SWMM networks with deduplication and automatic configuration.

## fix_InfoSWMM_Import_UI.rb

**Purpose:** User interface script - collects user input and launches the Exchange script.

**What it does (in 1-2 sentences):** Prompts user to select an InfoSWMM .mxd file, reads scenario names from SCENARIO.DBF, validates database connection, and launches the Exchange script for backend processing.

**Hardening applied:**
- Added `frozen_string_literal: true` pragma for immutability
- Wrapped entire main logic in begin/rescue/ensure block for robust error handling
- Validates WSApplication.current_database is not nil before proceeding
- Checks for user cancellation on all input dialogs and exits gracefully
- Added nil-safety checks with `&.` operator on optional method returns
- File handles opened via block form `File.open(path) do |f|`
- Progress logging with `puts "[#{Time.now}] ..."` timestamps for long operations
- Validates config file creation before launching Exchange script
- Cleanup of resources in ensure block even on errors

**How to run it:** Open ICM database, Network → Run Ruby Script → Select this file, follow prompts to choose .mxd and scenarios.

---

## fix_InfoSWMM_Import_Exchange.rb

**Purpose:** Backend ICM Exchange script that performs the heavy lifting of the multi-scenario import (Phases 1, 1.5, 2, 2.5). Launched automatically by the UI script.

**What it does (in 1-2 sentences):** Reads the JSON config written by the UI script, opens the target ICM database (verifying GUID), imports each InfoSWMM scenario into its own model group, deduplicates Rainfall/Inflow events, builds a merged network, and creates SWMM runs.

**Hardening applied:**
- `# frozen_string_literal: true` pragma at top
- Comprehensive header comment block (purpose, inputs, outputs, UI/EX type, hardening notes)
- Outer `begin / rescue / ensure` wraps the entire run; `ensure` always closes the log file and any open merged network handle
- Validates `WSApplication.open(...)` result is not nil and verifies database GUID matches expected before any writes
- Lock-file detection guarded against missing directories
- File handles use block form `File.open(path) do |f| ... end` (config read/write, JSON parsing)
- Nil-safety with `&.` on optional chains (e.g. `base_net&.row_objects(...)`)
- Timestamped progress logs via `stamp("...")` helper
- Transaction rollback retained on per-scenario errors
- Original phase-by-phase behaviour preserved verbatim
