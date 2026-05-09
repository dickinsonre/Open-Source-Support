# 0015 - Export SWMM5 Calibration Files - Fixed Scripts

13 SWMM5 calibration exporters. Each takes the user's current selection and writes Day/Time/Value rows in SWMM5 calibration format. Hardening applied to every fix_: `frozen_string_literal`, top-level `begin/rescue/ensure`, timestamped logging, network/timesteps validation, per-row rescue with nil-safe `ro.results(field)` access, time-interval validation, summary line printed at end.

---

## fix_hw_UI_script.rb
- **Original purpose:** Export node FloodDepth to SWMM5 calibration format (Day Time Value).
- **Hardening:** timestep validation, ts size match, idx-based time calc, processed/skipped/errors counters.
- **How to run:** open network with results, select nodes, run; copy console output into a calibration file.

## fix_hw_UI_script._groundwater_flow.rb
- **Original purpose:** Export subcatchment groundwater flow (RUNOFF series) for selected hw_subcatchment.
- **Hardening:** per-row rescue, ts.size match, nil-safe results.
- **How to run:** select subcatchments, run; copy console output.

## fix_hw_UI_scrip_downstream_velocity.rb
- **Original purpose:** Export conduit ds_vel for selected links.
- **Hardening:** asset_id falls back to sel.id; nil-safe row access.

## fix_hw_UI_script_downstream flow.rb
- **Original purpose:** Export conduit ds_flow with optional asset_mapping (InfoWorks->SWMM5 IDs).
- **Hardening:** asset_id fallback, nil-safe results.

## fix_hw_UI_script_downstream_depth.rb
- **Original purpose:** Export conduit ds_depth (note: original time_interval = (ts[1]-ts[0])*86400; preserved verbatim).
- **Hardening:** as above; original behaviour preserved.

## fix_hw_UI_script_groundwater_elevation.rb
- **Original purpose:** Export hw_subcatchment groundwater elevation (RUNOFF field used as elevation series).
- **Hardening:** as above.

## fix_hw_UI_script_node_flood_depth.rb
- **Original purpose:** Same intent as fix_hw_UI_script.rb (node FloodDepth) but kept as a separate name.
- **Hardening:** as above.

## fix_hw_UI_script_node_lateral_inflow.rb
- **Original purpose:** Export node QNODE (lateral inflow) for selected nodes.
- **Hardening:** as above.

## fix_hw_UI_script_node_level.rb
- **Original purpose:** Export node DEPNOD (water depth) for selected nodes.
- **Hardening:** as above.

## fix_hw_UI_script_runoff.rb
- **Original purpose:** Export hw_subcatchment RUNOFF for selected subcatchments.
- **Hardening:** as above.

## fix_hw_UI_script_upstream =low.rb
- **Original purpose:** Export conduit us_flow with asset_mapping (filename typo `=low` preserved).
- **Hardening:** asset_id fallback, nil-safe.

## fix_hw_UI_script_upstream_depth.rb
- **Original purpose:** Export conduit us_depth (preserves original time_interval = (ts[1]-ts[0])*86400).
- **Hardening:** as above.

## fix_hw_UI_script_upstream_velocity.rb
- **Original purpose:** Export conduit us_vel.
- **Hardening:** as above.

---

**How to run any of these:** Open ICM InfoWorks network with simulation results loaded, select the appropriate row type (nodes / conduits / subcatchments) and run the script. Copy the console output (everything between the `;` header and `;------- Export Summary -------`) into a `.dat` file for use as SWMM5 calibration data.
