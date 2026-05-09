# Folder 0021 - Change the Geometry or Rename IDs

Hardened `fix_*.rb` versions of every original script. All add
`# frozen_string_literal: true`, a header block, begin/rescue/ensure,
validation of network/selection/prompt input, polygon vertex count >= 3,
link bends >= 2 vertices, transaction-rollback on error, per-row rescue,
and timestamped progress logging.

## fix_1_split_link_into_chunks.rb
Splits each selected wn_pipe into evenly sized chunks of length
`DEFAULT_CHUNK_SIZE` using `InnoSpatial.split_link_into_chunks`.

Hardening:
- Validates network and selection
- Validates `bends` length >= 4 (>= 2 vertices) before splitting
- Transaction wrapped in rescue with `transaction_rollback`
- Per-link rescue

How to run: select wn_pipe rows, optionally edit `DEFAULT_CHUNK_SIZE`, then run.

## fix_2_split_links_around_node.rb
For every selected node, splits each us/ds link a configurable distance away.

Hardening:
- Prompts and validates the distance (not nil, not empty, > 0)
- Validates network and selection
- Transaction-rollback on error; per-node rescue

How to run: select nodes, run, enter distance.

## fix_Get Minimum X,Y for All Nodes.rb
Compute and print min/max X/Y over every node and the ICM version string.

Hardening:
- Validates network and node collection
- Skips nodes with nil x/y, prints considered/skipped counts

How to run: open the network and execute as a UI script.

## fix_UI-RenameNodeLinks.rb
Auto-rename every selected node and selected link via `autoname`.

Hardening:
- Validates network and that the selection is not empty
- Transaction wrapped in rescue with `transaction_rollback`
- Per-row rescue, separate node/link counters in log

How to run: select nodes/links and run as a UI script.

## fix_UI_4_Sides_script_ Change Subcatchment Boundaries.rb
Replace each selected hw_2d_infiltration_zone polygon with a rectangle.

Hardening:
- Validates network and collection
- Validates polygon has >= 3 vertices
- Transaction-rollback on error; per-polygon rescue

How to run: select hw_2d_infiltration_zone rows and run.

## fix_UI_5_Sides_script_ Change Subcatchment Boundaries.rb
Replace each selected hw_subcatchment polygon with a regular pentagon.

Hardening: same vertex / transaction guards as the rectangle script.

How to run: select hw_subcatchment rows and run.

## fix_UI_Generic_Sides_ Change Subcatchment Boundaries.rb
Replace each selected hw_subcatchment polygon with a regular N-sided polygon
(default 19).

Hardening: same vertex / transaction guards as the other shape scripts.

How to run: edit `NUMBER_OF_SIDES`, select rows, run.

## fix_hw_UI_script_Add Nine 1D Results Points.rb
For each selected hw_conduit, add nine `hw_1d_results_point` rows at 10/20/.../90%.

Hardening:
- Validates network and required collections
- Validates us/ds node lookups returned non-nil and have valid coordinates
- Per-conduit rescue
- Transaction-rollback on error

How to run: select hw_conduit rows and run.

## fix_UI_script_ Change Subcatchment Boundaries.rb
Sequentially reshape every selected hw_subcatchment polygon through five
geometries: rectangle -> hexagon -> pentagon -> nonagon -> 7-gon.

Hardening:
- Validates network and collection
- Each pass uses its own `transaction_begin`/`commit` with rollback on error
- Per-polygon rescue inside each pass

How to run: select hw_subcatchment rows and run.

## fix_pudgy penguin subs.rb
Universal Polygon Geometry & ID Changer.  Auto-detects hw/sw network and
reshapes selected subcatchments to RECTANGLE / regular POLYGON / CUSTOM
(penguin) shape.

Hardening:
- Validates network and subcatchment table
- Validates polygon has >= 3 vertices and area-preservation math handles
  zero-area templates
- Transaction-rollback on error; per-polygon rescue

How to run: edit constants at top (SHAPE_TYPE etc), select rows, run.

## fix_spatial.rb
Hardened InnoSpatial helpers (split_link_into_chunks,
split_links_around_node, split_link_at_distance, link_length, distance,
lerp).  Library only - required by the split-link scripts.

Hardening:
- Nil-safety on `bends`, `us_node`, `ds_node`
- Validates link has >= 2 vertices and positive length before splitting
- Rejects zero/negative distance and chunk_size
- `lerp` clamped to [0,1]
- Catches and logs per-link errors so a batch run continues

How to run: required automatically by the split scripts via
`require_relative 'spatial'` (filename of the original).  This fix file
preserves the same module name (`InnoSpatial`) so callers can be pointed
at it by editing their `require_relative` line.

## fix_swmm_UI_script_ Change Subcatchment Boundaries.rb
Prompt-driven version: asks for SWMM/InfoWorks and number of sides, then
reshapes selected subcatchments.

Hardening:
- Validates the prompt was not cancelled
- Validates the chosen sides count (3..50)
- Resolves and validates the subcatchment table
- Transaction-rollback on error; per-polygon rescue

How to run: select subcatchments and run; answer the prompt.
