# Ruby Script Robustness Pass — Master Index

Every `.rb` file under `02 SWMM/` was paired with a `fix_<name>.rb` sibling that adds a **robustness layer** while preserving original behavior.

- **Folders processed:** 26
- **Original scripts:** 279
- **fix\_ scripts written:** 279
- **Per-folder docs:** `_Fixes.md` (markdown) + `_Summary.html` (styled standalone)

## What "robustness" means here

Each `fix_*.rb` adds a consistent hardening layer:

- `# frozen_string_literal: true` pragma at top.
- A header docblock stating purpose, inputs, outputs, whether it's a UI script or an ICM Exchange (EX) script, and what was hardened.
- `begin / rescue => e / ensure` around the main logic so transactions always commit-or-rollback, log files always close, and tracebacks are surfaced cleanly.
- Pre-flight validation: `WSApplication.current_network` not nil, selection non-empty, prompts not cancelled, file paths exist via `File.exist?`.
- File I/O via the block form `File.open(...) do |f| ... end` and `CSV.open(...) do |csv| ... end` so handles always close.
- Timestamped progress logging (`[HH:MM:SS] ...`) so long batches show liveness.
- Nil-safety with `&.` and explicit `next if ro.nil?` guards inside loops.
- Per-row `rescue` so a single malformed row doesn't abort an entire batch.
- `transaction_begin` / `transaction_commit` paired with `transaction_cancel` (or `rollback`) in the rescue branch — only when the original used transactions.
- For very large Exchange importers (>1000 lines), `fix_` is implemented as a thin **delegating wrapper** that adds the outer safety net via `Kernel#load`, preserving the original logic verbatim.

## Folder index

| Folder | Originals | fix\_ | Summary |
| --- | ---: | ---: | --- |
| **0000 - InfoSWMM Multi-Scenario Import** &mdash; Multi-scenario importer that pulls InfoSWMM exports into ICM with phase-based workflow (UI + Exchange). | 2 | 2 | [HTML](./0000%20-%20InfoSWMM%20Multi-Scenario%20Import/_Summary.html) |
| **0000 - PCSWMM Import to ICM SWMM** &mdash; PCSWMM .inp ingestion into ICM SWMM via UI prompts and an Exchange worker. | 2 | 2 | [HTML](./0000%20-%20PCSWMM%20Import%20to%20ICM%20SWMM/_Summary.html) |
| **0001 - Element and Field Statistics** &mdash; Statistics over element fields (lengths, diameters, depression storage, user numbers, all-parameter stats). | 18 | 18 | [HTML](./0001%20-%20Element%20and%20Field%20Statistics/_Summary.html) |
| **0002 - Tracing Tools** &mdash; Network traversal: upstream/downstream traces, Dijkstra shortest path, boundary trace, area accumulators. | 22 | 22 | [HTML](./0002%20-%20Tracing%20Tools/_Summary.html) |
| **0003 - Scenario Tools** &mdash; Scenario generators (alphabetic, numbered, parametric) and DWF/scenario importers from CSV. | 10 | 10 | [HTML](./0003%20-%20Scenario%20Tools/_Summary.html) |
| **0004 - Scenario Sensitivity - InfoWorks** &mdash; Parametric sensitivity scenarios over GIM and link data. | 2 | 2 | [HTML](./0004%20-%20Scenario%20Sensitivity%20-%20InfoWorks/_Summary.html) |
| **0005 - Import Export of Data Tables** &mdash; Bulk CSV/snapshot export-import for nodes, conduits, pumps, weirs, orifices, subcatchments, parameters. | 40 | 40 | [HTML](./0005%20-%20Import%20Export%20of%20Data%20Tables/_Summary.html) |
| **0006 - ICM SWMM vs ICM InfoWorks All Tables** &mdash; Side-by-side enumeration of ICM SWMM and ICM InfoWorks table names, run params, sensors. | 11 | 11 | [HTML](./0006%20-%20ICM%20SWMM%20vs%20ICM%20InfoWorks%20All%20Tables/_Summary.html) |
| **0007 - Hydraulic Comparison Tools for ICM InfoWorks and SWMM** &mdash; Hydraulic math: Manning's, Kutter, tau/shear stress, HEC-22 inlet checks. | 7 | 7 | [HTML](./0007%20-%20Hydraulic%20Comparison%20Tools%20for%20ICM%20InfoWorks%20and%20SWMM/_Summary.html) |
| **0008 - Database Field Tools for Elements and Results** &mdash; Field/schema introspection: list every input variable, every result, network field structures. | 28 | 28 | [HTML](./0008%20-%20Database%20Field%20Tools%20for%20Elements%20and%20Results/_Summary.html) |
| **0009 - Polygon Subcatchment Boundary Tools** &mdash; Polygon ops: result points, generic-sided shapes, create subs/nodes from polygons. | 6 | 6 | [HTML](./0009%20-%20Polygon%20Subcatchment%20Boundary%20Tools/_Summary.html) |
| **0010 - List all results fields with Stats** &mdash; Enumerate result fields and dump min/max/mean/std-dev per field for nodes, links, subcatchments, flap valves. | 7 | 7 | [HTML](./0010%20-%20List%20all%20results%20fields%20with%20Stats/_Summary.html) |
| **0011 - Get results from all timesteps in the IWR File** &mdash; Time-series extraction for every timestep across links, nodes, subcatchments, manholes. | 11 | 11 | [HTML](./0011%20-%20Get%20results%20from%20all%20timesteps%20in%20the%20IWR%20File/_Summary.html) |
| **0012 - ICM InfoWorks Results to SWMM5  Summary Tables** &mdash; Replicate EPA SWMM5-style summary tables (Link Flow, Node Depth, Surcharge, Runoff) from ICM results. | 6 | 6 | [HTML](./0012%20-%20ICM%20InfoWorks%20Results%20to%20SWMM5%20%20Summary%20Tables/_Summary.html) |
| **0013 - SUDS or LID Tools** &mdash; Sustainable Urban Drainage / LID controls: bulk creation and CSV export. | 4 | 4 | [HTML](./0013%20-%20SUDS%20or%20LID%20Tools/_Summary.html) |
| **0014 - InfoSewer to ICM Comparison Tools** &mdash; InfoSewer steady-state report parsers, peaking-factor calculators, subcatchment generators from imported manholes. | 7 | 7 | [HTML](./0014%20-%20InfoSewer%20to%20ICM%20Comparison%20Tools/_Summary.html) |
| **0015 - Export SWMM5 Calibration Files** &mdash; Export per-element time series in EPA SWMM5 .DAT calibration format (flow, depth, velocity, runoff, groundwater). | 13 | 13 | [HTML](./0015%20-%20Export%20SWMM5%20Calibration%20Files/_Summary.html) |
| **0016 - InfoSWMM and SWMM5 Tools in Ruby** &mdash; InfoSWMM subcatchment manager, SWMM5 .RPT parser, inflow file builder. | 3 | 3 | [HTML](./0016%20-%20InfoSWMM%20and%20SWMM5%20Tools%20in%20Ruby/_Summary.html) |
| **0017 - Subcatchment Grid and Tabs Tools** &mdash; Subcatchment grid/tabs: land-use, runoff surfaces, copy/move pumps, nearest-node connections, multi-load copies. | 19 | 19 | [HTML](./0017%20-%20Subcatchment%20Grid%20and%20Tabs%20Tools/_Summary.html) |
| **0018 - Create Selection list using a SQL query** &mdash; Build selection lists from SQL, generate per-row reports, find isolated nodes, detect duplicate links. | 6 | 6 | [HTML](./0018%20-%20Create%20Selection%20list%20using%20a%20SQL%20query/_Summary.html) |
| **0019 - Node Connection Tools** &mdash; Detect dry pipes, bifurcation nodes, header nodes via graph traversal. | 4 | 4 | [HTML](./0019%20-%20Node%20Connection%20Tools/_Summary.html) |
| **0020 - All Node, Subs and Link IDs Tools** &mdash; Bulk rename of node/sub/link IDs with collision detection; duplicate ID reporting. | 5 | 5 | [HTML](./0020%20-%20All%20Node%2C%20Subs%20and%20Link%20IDs%20Tools/_Summary.html) |
| **0021 - Change the Geometry or Rename IDs** &mdash; Split links, change subcatchment polygon shapes, add 1D results points, rename objects. | 12 | 12 | [HTML](./0021%20-%20Change%20the%20Geometry%20or%20Rename%20IDs/_Summary.html) |
| **0022 - Hackathon AWI OffShoots** &mdash; Folder-mode multi-scenario importers and SWMM5-to-ICM cleanup variants. | 10 | 10 | [HTML](./0022%20-%20Hackathon%20AWI%20OffShoots/_Summary.html) |
| **0024 - Utilities** &mdash; Cross-network comparisons, asset-id mappers, network-info utilities. | 13 | 13 | [HTML](./0024%20-%20Utilities/_Summary.html) |
| **0025 - Miscellaneous** &mdash; Sandbox demos, Bill James similarity index, prompt-layout examples, parameter listings. | 11 | 11 | [HTML](./0025%20-%20Miscellaneous/_Summary.html) |

## Notable bug fixes uncovered during the pass

- `0017 - Subcatchment Grid and Tabs Tools/Move_Copy_Impored_Pumps.rb` called undefined `new_pump_ro()` &mdash; the fix\_ version uses `net.new_row_object('hw_pump')`.
- `0017 - Subcatchment Grid and Tabs Tools/*Copy selected subcatchments*.rb` opened/committed transactions per-copy inside the inner loop &mdash; fixed to one transaction wrapping the whole batch.
- `0017` nearest-node scripts replaced magic `999999999.9` with `Float::INFINITY` and pre-built node arrays for O(N+M) instead of O(N×M).
- `0018 - Create Selection list using a SQL query/UI_Script.rb` had a SQL syntax error (extra trailing quote) &mdash; fixed in the fix\_ version.
- `0002 - Tracing Tools/Sum_Selected_Total_Area.rb` had `row   objects` with a triple space typo &mdash; corrected to `row_objects`.

## How to use a fix\_ script

1. Open ICM (or ICMExchange.exe for EX scripts).
2. Open the relevant network.
3. Run the `fix_<name>.rb` instead of the original. Behaviour is identical, but you get clean error messages, transaction safety, and progress logs in the console.

Originals are untouched and remain in their folders.
