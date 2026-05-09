# 0017 - Subcatchment Grid and Tabs Tools - Fixed Scripts

19 fix_ scripts covering subcatchment creation, copy/clone, nearest-node connection, runoff-surface/land-use reporting, and ICM InfoWorks vs ICM SWMM diagnostics.

Hardening applied to every fix_: `frozen_string_literal`, top-level `begin/rescue/ensure`, timestamped `[HH:MM:SS]` progress logging, network/selection validation, nil-safe field access (`&.`), per-row rescue, single-transaction batches with rollback on raise, and `File.open` block form for any file output.

---

## fix_change_the_runoff_surface_grid.rb
- **Original purpose:** Modify hw_runoff_surface fields in bulk based on filter criteria.
- **Hardening:** kept from prior pass; consistent with the conventions above.
- **How to run:** open network in edit mode and run.

## fix_ICM InfoWorks vs ICM SWMM Subcatchment.rb
- **Original purpose:** Diagnostic that lists tables in current vs background networks and counts hw_subcatchment / sw_subcatchment rows.
- **Hardening:** nil-safe network checks, per-iteration rescue, helper `list_tables` method.
- **How to run:** open both InfoWorks (current) and SWMM (background) networks, run.

## fix_Model_Evaluation_Logic.rb
- **Original purpose:** Master report comparing InfoWorks vs SWMM subcatchments across area, slope, roughness, depression storage and impervious % using `surface_type` to match Pervious/Impervious surfaces. Optional CSV export.
- **Hardening:** safe_rows/safe_get/try_fields helpers, per-row rescue, CSV via `File.open` with rescue.
- **How to run:** open both networks, set CSV_PATH constant, run.

## fix_Move_Copy_Impored_Pumps.rb
- **Original purpose:** Find links tagged `user_text_10 == 'Pump'` and create a hw_pump row for each.
- **Bug fix:** original called `new_pump_ro()` which is undefined; fixed to `net.new_row_object('hw_pump')`.
- **Hardening:** transaction rollback on raise; per-link rescue.
- **How to run:** import pumps as links with user_text_10='Pump', then run.

## fix_Nearest Storage Node.rb
- **Original purpose:** For each subcatchment with empty node_id, set node_id to the nearest hw_node where node_type='storage'.
- **Hardening:** pre-build storage-node array (O(N+M)), per-row rescue, nil-safe x/y, transaction rollback.
- **How to run:** open network in edit mode and run.

## fix_Step1a_Create_Subcatchments.rb
- **Original purpose:** Create one hw_subcatchment per unique node coordinate (default total_area=0.10).
- **Hardening:** transaction rollback on raise, per-row rescue, nil-safe x/y.
- **How to run:** open network in edit mode and run.

## fix_Step7a_InfoSewer_subcatchment_copy_for_ten_loads.rb
- **Original purpose:** Copy each selected hw_subcatchment with `_copy` suffix.
- **Hardening:** wrapped whole batch in one transaction (was per-copy), per-row rescue.
- **How to run:** select subcatchments and run.

## fix_UI_script_Runoff surfaces from selected subcatchments.rb
- **Original purpose:** Starting from selected hw_runoff_surface rows, select every hw_land_use referencing them and every hw_subcatchment whose land_use_id matches.
- **Hardening:** per-row rescue, nil-safe runoff_index lookups, breaks early once a slot match is found per land_use.
- **How to run:** select runoff_surface rows in grid, run.

## fix_hw_UI_Script_ Land Use with Runoff Surfaces Table.rb
- **Original purpose:** Print hw_land_use rows interleaved with their slot-by-slot hw_runoff_surface details.
- **Hardening:** per-row rescue.
- **How to run:** open network and run.

## fix_hw_UI_Script_InfoWorks Land Use Tables.rb
- **Original purpose:** Print all hw_land_use rows with their slot 1..12 runoff_index_N and p_area_N values.
- **Hardening:** per-row rescue.

## fix_hw_UI_Script_Runoff Surface Tables.rb
- **Original purpose:** Print hw_runoff_surface full parameter set and show a configuration prompt.
- **Hardening:** per-row rescue; prompt failure (e.g. running headless) is logged but does not abort the report.

## fix_hw_UI_script Connect subcatchment to nearest node.rb
- **Original purpose:** For each selected hw_subcatchment, find the nearest selected hw_node and write its id.
- **Hardening:** uses `Float::INFINITY` (was 999999999.9), per-row rescue, transaction rollback.

## fix_hw_UI_Script_Sub, Land Use with Runoff Surfaces Table.rb
- **Original purpose:** Combined Land Use + Runoff Surfaces + Subcatchment Grid report.
- **Hardening:** per-row rescue, nil-safe field iteration.

## fix_hw_UI_Script_Subcatchment Grid Area Table.rb
- **Original purpose:** Print hw_subcatchment grid (ID, Land Use, Total Area, contributing area, measurement type) plus area_absolute_N and area_percent_N for slots 1..12.
- **Hardening:** per-row rescue.

## fix_hw_UI_script_Copy selected subcatchments User Defined Times.rb
- **Original purpose:** Copy each selected hw_subcatchment N times (default 5) with `_c_<n>` suffix.
- **Hardening:** single transaction (was per-copy), per-row rescue.

## fix_hw_UI_script_Copy selected subcatchments with user suffix.rb
- **Original purpose:** Copy each selected hw_subcatchment once per suffix in the list (default Horton/GreenAmpt/Constant) using `_<suffix>` naming.
- **Hardening:** single transaction, per-row rescue.

## fix_sw_UI_script Connect subcatchment to nearest node.rb
- **Original purpose:** SWMM-side: for each selected sw_subcatchment, find nearest selected sw_node and write to outlet_id.
- **Hardening:** Float::INFINITY, per-row rescue, transaction rollback.

## fix_sw_UI_script_Copy selected subcatchments User Defined Times.rb
- **Original purpose:** SWMM-side copy x N (default 5) with `_c_<n>` suffix.
- **Hardening:** single transaction, per-row rescue.

## fix_sw_UI_script_Copy selected subcatchments with user suffix.rb
- **Original purpose:** SWMM-side copy with custom suffix list (default Horton/GreenAmpt/Constant).
- **Hardening:** single transaction, per-row rescue.

---

**How to run any of these:** open the appropriate ICM (InfoWorks or SWMM) network in edit mode, make any required selection (per script), and run from the Network -> Run Ruby Script menu.
