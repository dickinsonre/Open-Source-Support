# PCSWMM Import to ICM SWMM - Hardened Scripts

Folder: `0000 - PCSWMM Import to ICM SWMM`

Purpose: Import PCSWMM models (.pcz files) into InfoWorks ICM as SWMM networks with automatic field truncation and cleanup.

## fix_PCSWMM_Import_UI.rb

**Purpose:** User interface script - collects user input and launches the Exchange script.

**What it does (in 1-2 sentences):** Prompts user to select a .pcz file, validates the database is open, captures database GUID for verification, and launches the Exchange script for the actual import.

**Hardening applied:**
- Added `frozen_string_literal: true` pragma
- Wrapped main logic in begin/rescue/ensure for comprehensive error handling
- Validates WSApplication.current_database is not nil before proceeding
- Nil-safety checks on all user input returns with `&.`
- File handles opened via block form `File.open do |f|`
- Config file validated before proceeding
- Graceful handling of user cancellations at all input dialogs
- Progress logging with timestamps on all key operations
- Cleanup of config file in ensure block even on errors
- Database GUID captured for cross-validation in Exchange script

**How to run it:** Open ICM database, select Network → Run Ruby Script, choose this file, follow prompts to select .pcz file and model group name.

---

## fix_PCSWMM_Import_Exchange.rb

**Purpose:** Backend ICM Exchange script that performs the actual PCSWMM-to-ICM import. Launched automatically by the UI script.

**What it does (in 1-2 sentences):** Reads the JSON config written by the UI script, opens the target ICM database (verifying GUID), extracts the .pcz archive via PowerShell `Expand-Archive`, locates the INP file, truncates fields longer than 100 characters, creates a model group, imports the INP, decodes URL-encoded names, removes empty label lists, and commits the network.

**Hardening applied:**
- `# frozen_string_literal: true` pragma at top
- Comprehensive header comment block (purpose, inputs, outputs, UI/EX type, hardening notes)
- Outer `begin / rescue / ensure` wraps the entire run; `ensure` always closes the log file, closes the network if open, and removes the temp extraction directory
- Validates `WSApplication.open(...)` result is not nil and verifies database GUID matches expected before any writes
- All file handles open via block form `File.open(path) do |f| ... end` (config JSON read, INP truncation writer)
- Nil-safety with `&.` on optional chains (e.g. `net&.commit(...)`, `log_file&.puts`)
- Timestamped progress logs via `stamp("...")` helper
- Original PCSWMM-import behaviour preserved verbatim (truncation thresholds, PowerShell extraction, label-list cleanup, URL-decoded names)
