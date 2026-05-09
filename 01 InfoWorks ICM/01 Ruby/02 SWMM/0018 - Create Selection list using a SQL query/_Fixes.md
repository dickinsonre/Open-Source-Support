# Folder 0018 - Create Selection list using a SQL query

This folder contains hardened `fix_*.rb` versions of each original Ruby script.
All scripts add: `# frozen_string_literal: true`, header block, begin/rescue/ensure,
nil-safety, timestamped progress logging, and preserve original behaviour.

## fix_UI-CreateSelectionList.rb
Save current network selection (nodes + links) as Selection List(s) under the
configured Model Group.

Hardening:
- Validates current database and network not nil
- Falls back from `model_object_from_type_and_id` to `find_root_model_object`
- Counts selected items and warns if selection is empty
- Wraps the workflow in begin/rescue/ensure with timestamped log lines

How to run: open the network in ICM UI, ensure something is selected, edit the
`MODEL_GROUP_NAME` constant, then Network -> Run Ruby Script.

## fix_UI-Reports-CreateIndividualForSelection.rb
Generate an individual Word report per row in the configured CAMS table to
`c:\temp`.

Hardening:
- Validates network not nil
- `FileUtils.mkdir_p` to ensure output dir exists
- Per-row `rescue` so a single failure does not abort the run
- Timestamped progress logging and per-table count
- Suppresses message_box failures in headless contexts

How to run: select rows in the CAMS table, edit `TABLES`/`OUTPUT_DIR`, then run.

## fix_UI-Reports-CreateIndividualForSelection_folder.rb
Same as above but prompts the user for the output folder.

Hardening:
- Validates network not nil and folder dialog not cancelled
- `FileUtils.mkdir_p` and per-row rescue
- Timestamped progress logging

How to run: select rows in the CAMS table and execute - pick an export folder.

## fix_UI-SelectIsolatedNodes.rb
Select all nodes that have no upstream link, no downstream link, and no
lateral pipes (truly isolated).

Hardening:
- Validates network and node collection
- Nil-safe access to `navigate('lateral_pipe')`
- Reports total inspected vs selected counts

How to run: open the network and execute as a UI script.

## fix_UI_Script  Select links sharing the same us and ds node ids.rb
Select duplicate / parallel links sharing the same upstream and downstream
node-id pair.

Hardening:
- Validates network and link collection
- Skips links whose us/ds id is nil
- Reports total scanned, duplicate-pair groups and selected count

How to run: open the network and execute as a UI script.

## fix_UI_Script.rb
Run `flags.value='ISAC'` SQL across `_links`, `_nodes`, `_subcatchments` and
save the resulting selection as a Selection List under a named Model Group.

Hardening:
- Validates database, network and group lookup not nil
- Each `run_SQL` wrapped in its own rescue
- Fixes the original syntax bug (extra trailing quote) in the SQL
- Timestamped log lines and final confirmation

How to run: edit `MODEL_GROUP_NAME` and execute as a UI script.
