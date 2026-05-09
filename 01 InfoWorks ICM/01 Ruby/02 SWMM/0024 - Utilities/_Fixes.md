# 0024 - Utilities - Hardened Wrapper Notes

This folder collects comparison utilities and small ad-hoc tools that read
ICM networks (often `current_network` and `background_network` together).
Each `fix_<original>.rb` is a thin, hardened wrapper around its original
that preserves behavior via `Kernel#load` and adds:

- `# frozen_string_literal: true` pragma
- File-level header (purpose, inputs, outputs, UI/EX, hardening notes)
- `begin / rescue StandardError / rescue Interrupt / rescue SystemExit / ensure`
- `WSApplication` availability check (these are UI scripts)
- Validation that `current_network` is loaded
- Where the script reads two networks, validation that BOTH
  `current_network` AND `background_network` are loaded
- `transaction_rollback` in the rescue path for scripts that mutate the
  network (preserves data integrity if a write fails mid-transaction)
- Timestamped wrapper-level progress logging on stdout

Behavior of the underlying comparison / statistics logic is preserved.

## fix_Compare ICM trade flow to SWMM Base Flow.rb
Wraps the trade_flow vs base_flow comparison and optional copy-over.
Validates both networks; rollback on failure.

## fix_Compare InfoWorks to SWMM for Links.rb
Wraps the hw_conduit vs sw_conduit attribute comparison.
Validates both networks.

## fix_Compare InfoWorks to SWMM for Nodes.rb
Wraps the hw_node vs sw_node attribute comparison.
Validates both networks.

## fix_Compare InfoWorks to SWMM for Subcatchment and Node Inflows.rb
Wraps the multi-attribute subcatchment vs node comparison with optional
copy-over flags. Validates both networks; rollback on failure.

## fix_ICM_Infoworks_Flows_Only.rb
Wraps the single-network flow-summary tool. Validates current_network only.

## fix_asset_id_to_icm_link_id.rb
Wraps the asset_id-to-ICM-link-id remapper. Validates current_network.

## fix_current_background_conduit_compare.rb
Wraps the conduit parameter comparison utility. Validates both networks.

## fix_current_background_node_compare.rb
Wraps the node parameter comparison utility. Validates both networks.

## fix_icm_infoworks_node_link_results_stats.rb
Wraps the InfoWorks-side time-integrated results stats utility.
Validates current_network.

## fix_icm_swmm_missing_link_us_ds_nodes.rb
Wraps the SWMM topology-inference utility. Validates current_network.

## fix_icm_swmm_node_link_results_stats.rb
Wraps the SWMM-side time-integrated results stats utility.
Validates current_network.

## fix_sonnet_exchange_centroid_bn_cn_networks.rb
Wraps the centroid / nearby-objects / unique-objects diagnostic.
Validates both networks; rollback on failure.

## fix_what_network_am_I_using.rb
Wraps the trivial network-type identifier. Reports clearly if no network
is loaded.
