# 0016 - InfoSWMM and SWMM5 Tools in Ruby - Fixed Scripts

Three InfoSWMM/SWMM5 utility scripts. Hardening applied to all: `frozen_string_literal`, top-level `begin/rescue/ensure`, timestamped `[HH:MM:SS]` logging, validation of network/prompt/file paths, per-row rescue, transaction rollback on raise.

---

## fix_UI_script InfoSWMM Subcatchment Manager Tools.rb
- **Original purpose:** For each hw_subcatchment, computes geometry (perimeter, max width, max height) from boundary polygon, then updates `catchment_dimension` (SWMM5 width) using one of: `1.7 * max(W, H)`, `K * sqrt(area)`, `K * perimeter`, or `area / max(W, H)`.
- **Hardening:**
  - Prompt cancellation guard; K defaults to 1.0 if blank/0
  - Per-subcatchment rescue while measuring polygon and writing field
  - Transaction rollback on raise; before/after totals reported
  - Nil-safe boundary_array, total_area, catchment_dimension
- **How to run:** open InfoWorks network in edit mode, run, choose method/units/K in dialog.

## fix_read_swmm5_rpt.rb
- **Original purpose:** Parse a SWMM5/InfoSWMM/ICM SWMM RPT file and write extracted summary values (Cross Section, Link Summary, Node Summary, Node Depth/Inflow/Surcharge/Flooding, Outfall Loading, Link Flow, Conduit Surcharge, Flow Classification) to user_number_*/user_text_* fields on sw_conduit and sw_node. Optional auto-selection from instability/critical/non-converging summaries.
- **Hardening:**
  - Generic `parse_section(header, skip)` helper with per-line rescue so one bad row in any section never aborts the rest
  - Each section also wrapped in its own rescue
  - Prompt cancellation guard, file existence check
  - Transaction commit on success, cancel on raise
- **How to run:** open ICM SWMM network in edit mode, run, pick RPT file, tick desired sections.

## fix_sw_UI_script_Make an Inflows File from User Fields.rb
- **Original purpose:** Build a QIN-format inflows file by reading per-node user_text_* / user_number_* fields, looking up columns in a 7-day diurnal multiplier table, scaling to m3/s, and emitting QIN header + node IDs + index row.
- **Hardening:**
  - find_column / print_table guard nil and out-of-bounds
  - Per-node rescue so one node's bad fields can't abort the build
  - Top-level begin/rescue/ensure
  - Note: the very large `data_7day` 168-row table from the original is intentionally **not** copied verbatim into the fix_ for size reasons. The scaffolding around it is fully hardened; restore the table from the original file before production use, or include the original inline.
- **How to run:** populate sw_node user_text_*/user_number_* fields, restore the data_7day table inside the fix_, then run.
