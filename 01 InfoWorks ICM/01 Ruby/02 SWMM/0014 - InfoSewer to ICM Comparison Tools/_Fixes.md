# 0014 - InfoSewer to ICM Comparison Tools - Fixed Scripts

This folder contains hardened (`fix_*.rb`) versions of every Ruby script. Hardening applied to each: `frozen_string_literal`, top-level `begin/rescue/ensure`, timestamped `[HH:MM:SS]` progress logging, validation of network/selection/timesteps/files, nil-safe field access (`&.`), per-row `rescue` so a single bad row does not abort the run, transactions committed only on success and cancelled on raise, and `File.open`/`CSV.open` block forms.

---

## fix_PeakingFlowCalculator.rb
- **Original purpose:** Calculate design flows with peakable/unpeakable flow separation; apply peaking formulas (Harmon, Modified Harmon, Babbitt, custom).
- **Hardening:** transaction safety, parameter range validation, zero-division guards, progress logging, CSV with rescue.
- **How to run:** open InfoWorks ICM network in edit mode, run script, supply parameters via prompt, check console for summary.

## fix_hw_UI_script  InfoSewer Gravity Main Report, from ICM InfoWorks.rb
- **Original purpose:** For each selected hw_conduit, read us_depth/us_flow/ds_depth/ds_flow over all timesteps, compute means/min/max plus d/D and Q/Qfull, select top 10 by us_d/D and ds_d/D.
- **Hardening:** validates timesteps (>1) and capacity/conduit_height before division, per-link rescue, nil-safe row lookups, timestamped logging, ensures clear_selection runs.
- **How to run:** open network with results loaded, select conduits, run.

## fix_hw_UI_script InfoSewer Peaking Factors.rb
- **Original purpose:** Apply InfoSewer-style peaking factor (k * Q^p or alternative curve) and write base_flow / trade_flow / additional_foul_flow / conduit_flow on selected links.
- **Hardening:** detects read-only mode and skips Phase 2 cleanly, validates prompt cancellation, two-phase processing with per-link rescue, summary table printed at end.
- **How to run:** open network with results in edit mode, select links, run, fill in dialog.

## fix_hw_UI_Script_ Make_Subcatchments_From_Imported_InfoSewer_Manholes.rb
- **Original purpose:** Create one hw_subcatchment per unique (x, y) coordinate of imported InfoSewer manhole nodes.
- **Hardening:** validates collections, transaction rollback on raise, per-row rescue, default total_area=0.10 preserved.
- **How to run:** import manholes into ICM InfoWorks, then run the script.

## fix_read_infosewer_steady_state.rb
- **Original purpose:** Parse a single InfoSewer steady-state RPT file and print per-section statistics + CSV blocks for Loading Manholes / Pipes / Force Mains / Pumps.
- **Hardening:** prompt cancellation guard, file existence check, `File.foreach` streaming, per-line rescue (malformed lines skipped), section-flag dispatch.
- **How to run:** run script, pick RPT file, choose sections in dialog.

## fix_sw_UI_Script_ Make_Subcatchments_From_Imported_InfoSewer_Manholes.rb
- **Original purpose:** SWMM-side equivalent: create one sw_subcatchment per unique (x, y) of imported manhole nodes.
- **Hardening:** validates network/collections, transaction rollback on raise, per-row rescue, default area=0.10 preserved.
- **How to run:** import manholes into ICM SWMM, then run.

## fix_ui.script  Read InfoSewer Steady State Report File.rb
- **Original purpose:** Batch parser; user picks any file in/near a folder, finds every *.rpt nearby, parses each, computes per-file and aggregate statistics, exports CSVs.
- **Hardening:** prompt cancellation, smart root discovery, `File.foreach` streaming with per-line rescue, every CSV export wrapped in its own rescue so a single failure doesn't abort other exports.
- **How to run:** run, pick any RPT (or any file in the folder), choose options, review console + CSV output dir.
