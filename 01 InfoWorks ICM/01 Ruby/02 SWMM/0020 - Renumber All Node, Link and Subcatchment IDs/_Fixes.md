# Folder 0020 - All Node, Subs and Link IDs Tools

Hardened `fix_*.rb` versions of every original script. All add
`# frozen_string_literal: true`, a header block, begin/rescue/ensure with
transaction rollback on error, pre-flight collision detection for ID
renames, and timestamped progress logging.

## fix_DuplicateLinkIDs.rb
Detect and report duplicate link ids across all link sub-tables.

Hardening:
- Validates network and link collection
- Nil-safe on id/table
- Final summary with duplicate count

How to run: open the network and execute as a UI script.

## fix_hw_change All Node and Sub ID.rb
Sequentially rename every node and subcatchment in an InfoWorks (hw_*)
network (N_1, S_1, ...). Link rename is intentionally disabled to mirror
the original.

Hardening:
- Pre-flight collision detection - any proposed N_ / S_ id that conflicts
  with an existing id (excluding rows being renamed) aborts the run before
  any writes
- transaction_begin/commit wrapped in rescue with `transaction_rollback`
  on error
- Timestamped per-table count log

How to run: open an hw_* network and execute as a UI script. Read the log -
abort messages indicate manual cleanup is required.

## fix_hw_change All Node, Subs and Link ID.rb
Same as above but renames links too (L_n).

Hardening: identical strategy to the sister script with the addition of
link-id collision detection.

How to run: open an hw_* network and execute as a UI script.

## fix_sw_change All Node, Link  and Subs ID.rb
SWMM equivalent: rename every node, link and subcatchment in an sw_*
network using N_/L_/S_ prefixes.

Hardening: same pre-flight collision detection and transaction-rollback as
the hw_ variants.

How to run: open an sw_* network and execute as a UI script.

## fix_sw_change All Node, Subs and Link ID.rb
Functional duplicate of the previous script (kept for parity with the
original folder layout).

Hardening: identical to the sister script.

How to run: open an sw_* network and execute as a UI script.
