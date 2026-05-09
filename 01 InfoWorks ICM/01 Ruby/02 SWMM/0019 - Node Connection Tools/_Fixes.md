# Folder 0019 - Node Connection Tools

Hardened `fix_*.rb` versions of every original script. All add
`# frozen_string_literal: true`, a header block, begin/rescue/ensure,
nil-safety on graph traversal, timestamped progress logging, and preserve
original behaviour.

## fix_hw_dry pipes.rb
InfoWorks dry-pipe detection: walk downstream from every subcatchment outlet
node and select links never reached.

Hardening:
- Validates network, subcatchment, link, node collections
- Resets the `_seen` flag at the start so re-runs are reliable
- Nil-safe on each `ds_node` hop
- Timestamped log lines

How to run: open an hw_* network and execute as a UI script.

## fix_sw_dry pipes.rb
SWMM equivalent of the above (uses `outlet_id` and `sw_node`).

Hardening: same as the hw_ version.

How to run: open an sw_* network and execute as a UI script.

## fix_hw_sw_Bifurcation Nodes.rb
Select bifurcation nodes (us_node referenced by 2+ links).

Hardening:
- Validates network and link collection
- Nil-safe on us_node_id
- Per-node rescue around `row_object('_nodes', id)`

How to run: open the network and execute as a UI script.

## fix_hw_sw_Header Nodes.rb
Select header / most-upstream nodes (nodes that never appear as a link's
downstream node).

Hardening:
- Validates network, _nodes and _links collections
- Uses a `Set` for O(1) downstream-id lookup
- Nil-safe and per-node rescue

How to run: open the network and execute as a UI script.
