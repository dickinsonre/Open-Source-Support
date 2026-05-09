# 0002 - Tracing Tools - Fixes Summary

## Folder Purpose
Network tracing tools for upstream/downstream path analysis, subcatchment area calculations, and boundary condition traces. Includes Dijkstra shortest-path algorithms, incident-based traces, and various filtering criteria (invert level, pipe status, length accumulation).

## Fixes Applied

### fix_1_shortest_path_dijkstra.rb
**Original:** 1_shortest_path_dijkstra.rb  
**Purpose:** Dijkstra shortest path algorithm between 2 selected nodes.  
**Hardening:**
- Added begin/rescue/ensure error handling
- Input validation: network exists, exactly 2 nodes selected
- Nil-safe navigation with `&.` operator
- Progress logging to console

**How to Run:** UI script; select 2 nodes, run script; selected path shows in red.

---

### fix_2_boundary_trace.rb
**Original:** 2_boundary_trace.rb  
**Purpose:** Trace flow boundaries with exclusion logic (area, status, type).  
**Hardening:**
- Added begin/rescue/ensure error handling
- Input validation: 1 link selected
- Compact nil-safe node arrays
- Link count tracking in output

**How to Run:** UI script; select 1 link, run; trace highlights boundary-matching path.

---

### fix_Select Upstream Subcatchments from a Node with Multilinks.rb
**Original:** Select Upstream Subcatchments from a Node with Multilinks.rb  
**Purpose:** Select upstream subcatchments with hash-accelerated lookup.  
**Hardening:**
- Added begin/rescue/ensure error handling
- Hash-based node->subcatchment mapping (O(1) lookup)
- Visited tracking with _seen flag
- Cleanup of _seen markers in ensure block
- Area and count accumulation

**How to Run:** UI script; select node(s), run; outputs upstream subcatchment total area.

---

### fix_Sum_Selected_Total_Area SWMM.rb
**Original:** Sum_Selected_Total_Area SWMM.rb  
**Purpose:** Sum total area of selected SWMM subcatchments.  
**Hardening:**
- Added begin/rescue/ensure error handling
- Refactored function with return value
- Fixed missing nil check on network
- Message box confirmation with area

**How to Run:** UI script; select SWMM subcatchments, run; displays total area.

---

### fix_Sum_Selected_Total_Area.rb
**Original:** Sum_Selected_Total_Area.rb  
**Purpose:** Sum total area of selected InfoWorks subcatchments.  
**Hardening:**
- Added begin/rescue/ensure error handling
- Fixed syntax error in row_objects call (was row   objects)
- Refactored function for clarity
- Network validation

**How to Run:** UI script; select InfoWorks subcatchments, run; displays total area.

---

### fix_UI-IncidentTraceUpstream-Incident.rb
**Original:** UI-IncidentTraceUpstream-Incident.rb  
**Purpose:** Trace upstream from incident flooding node.  
**Hardening:**
- Added begin/rescue/ensure error handling
- Visited tracking with _seen flag
- Nil-safe node navigation
- Count accumulation for nodes/links

**How to Run:** UI script; select incident, run; selects upstream path from manhole.

---

### fix_UI-NodeTraceUpDownstream_ExcludeBy_InvertLevel.rb
**Original:** UI-NodeTraceUpDownstream_ExcludeBy_InvertLevel.rb  
**Purpose:** Trace with invert level > 15 exclusion filter.  
**Hardening:**
- Added begin/rescue/ensure error handling
- User choice validation (direction)
- Visited tracking with _seen flag
- Nil-safe node navigation

**How to Run:** UI script; select 1 manhole, run; choose up/downstream; traces excluding low invert pipes.

---

### fix_UI-NodeTraceUpDownstream_ExcludeBy_PipeStatus.rb
**Original:** UI-NodeTraceUpDownstream_ExcludeBy_PipeStatus.rb  
**Purpose:** Trace excluding pipes with status 'AB'.  
**Hardening:**
- Added begin/rescue/ensure error handling
- User choice validation (direction)
- Visited tracking with _seen flag
- Status filter check

**How to Run:** UI script; select 1 manhole, run; choose up/downstream; excludes pipes with status AB.

---

### fix_UI-NodeTraceUpDownstream_ExcludeBy_SumPipeLength.rb
**Original:** UI-NodeTraceUpDownstream_ExcludeBy_SumPipeLength.rb  
**Purpose:** Trace up/downstream, accumulating pipe length.  
**Hardening:**
- Added begin/rescue/ensure error handling
- User choice validation (direction)
- Visited tracking with _seen flag
- Length accumulation and rounding

**How to Run:** UI script; select 1 manhole, run; choose up/downstream; reports nodes, links, total length.

---

### fix_UI-NodeTraceUpstream.rb
**Original:** UI-NodeTraceUpstream.rb  
**Purpose:** Simple upstream trace from node.  
**Hardening:**
- Added begin/rescue/ensure error handling
- Visited tracking with _seen flag
- Nil-safe node navigation
- Count accumulation

**How to Run:** UI script; select 1 manhole, run; selects all upstream nodes/links.

---

### fix_UI-PipesTraceUpstream_SumPipeLengths.rb
**Original:** UI-PipesTraceUpstream_SumPipeLengths.rb  
**Purpose:** Trace upstream from pipe(s), sum lengths.  
**Hardening:**
- Added begin/rescue/ensure error handling
- Per-pipe _seen reset
- Nil validation on starting node
- Length accumulation per pipe

**How to Run:** UI script; select pipe(s), run; for each pipe outputs upstream node/link counts and total length.

---

### fix_UI-PipeTraceUpstream_SaveToSelectionList.rb
**Original:** UI-PipeTraceUpstream_SaveToSelectionList.rb  
**Purpose:** Trace upstream from pipe(s), save to selection list.  
**Hardening:**
- Added begin/rescue/ensure error handling
- Nil checks on asset group and selection list
- Per-pipe _seen reset
- Transaction implicit (save_selection handles it)

**How to Run:** UI script; select pipe(s), run; creates selection list in Asset Group 3 for each pipe's upstream path.

---

### fix_hw_QuickTrace.rb
**Original:** hw_QuickTrace.rb  
**Purpose:** Dijkstra quicktrace for InfoWorks networks.  
**Hardening:**
- Refactored into class with robustness
- Added begin/rescue/ensure error handling
- Input validation: 2 nodes selected
- Reachability check (target found or nil)
- Link type detection for length vs. fixed cost

**How to Run:** UI script; select 2 nodes, run; outputs shortest path with link lengths.

---

### fix_hw_QuickTrace_NG.rb
**Original:** hw_QuickTrace_NG.rb  
**Purpose:** Next-gen quicktrace (identical to hw_QuickTrace).  
**Hardening:**
- Same improvements as hw_QuickTrace
- Class-based implementation
- Robust error handling

**How to Run:** UI script; select 2 nodes, run; outputs shortest path with link lengths.

---

### fix_UI-PipesTraceUpstream_SumPipeLengths_WriteToField.rb
**Original:** UI-PipesTraceUpstream_SumPipeLengths_WriteToField.rb  
**Purpose:** Trace upstream from pipe, write total length to user_number_1 field.  
**Hardening:**
- Added begin/rescue/ensure with transaction rollback on error
- Nil validation on starting node
- Per-pipe _seen reset
- Explicit transaction commit/rollback

**How to Run:** UI script; select pipe(s), run; updates user_number_1 field with upstream path length.

---

### fix_UI_Script_ Calculate subcatchment areas in all nodes upstream a node.rb
**Original:** UI_Script_ Calculate subcatchment areas in all nodes upstream a node.rb  
**Purpose:** Traverse upstream, print each node's total subcatchment area.  
**Hardening:**
- Added begin/rescue/ensure error handling
- Nil-safe navigation of subcatchments
- Visited tracking with _seen flag
- Proper unsee_all cleanup

**How to Run:** UI script; hardcoded to node 44628801; outputs node_id:area pairs.

---

### fix_hw_Sum_Selected_Total_Area.rb
**Original:** hw_Sum_Selected_Total_Area.rb  
**Purpose:** Sum selected InfoWorks subcatchments with count.  
**Hardening:**
- Added begin/rescue/ensure error handling
- Function refactored with clear input/output
- Network validation

**How to Run:** UI script; select subcatchments, run; outputs total area and count.

---

### fix_hw_Upstream Subcatchments from an Outfall.rb
**Original:** hw_Upstream Subcatchments from an Outfall.rb  
**Purpose:** Select upstream subcatchments from node using hash acceleration.  
**Hardening:**
- Hash-based node->subcatchment mapping
- Visited tracking with _seen flag
- Nil-safe node navigation
- Area and count accumulation

**How to Run:** UI script; select node(s), run; selects all upstream subcatchments and reports totals.

---

### fix_sw_QuickTrace.rb
**Original:** sw_QuickTrace.rb  
**Purpose:** Dijkstra quicktrace for SWMM networks.  
**Hardening:**
- Class-based implementation
- Added begin/rescue/ensure error handling
- Input validation: 2 nodes selected
- SWMM-specific link.length attribute handling
- Reachability check

**How to Run:** UI script; select 2 SWMM nodes, run; outputs shortest path with link lengths.

---

### fix_sw_QuickTrace_SWMM..rb
**Original:** sw_QuickTrace_SWMM..rb  
**Purpose:** Duplicate SWMM quicktrace (identical to sw_QuickTrace).  
**Hardening:**
- Same improvements as sw_QuickTrace

**How to Run:** UI script; select 2 SWMM nodes, run; outputs shortest path with link lengths.

---

### fix_sw_Sum_Selected_Total_Area.rb
**Original:** sw_Sum_Selected_Total_Area.rb  
**Purpose:** Sum selected SWMM subcatchments with count.  
**Hardening:**
- Added begin/rescue/ensure error handling
- Uses sw_subcatchment.area (SWMM) instead of total_area
- Function refactored with clear input/output

**How to Run:** UI script; select SWMM subcatchments, run; outputs total area and count.

---

### fix_sw_Upstream Subcatchments from an Outfall.rb
**Original:** sw_Upstream Subcatchments from an Outfall.rb  
**Purpose:** Select upstream SWMM subcatchments using outlet_id mapping.  
**Hardening:**
- Hash-based outlet_id->subcatchment mapping (SWMM-specific)
- Visited tracking with _seen flag
- Nil-safe node navigation
- Area and count accumulation

**How to Run:** UI script; select node(s), run; selects all upstream SWMM subcatchments and reports totals.

---

## Common Hardening Patterns

All scripts include:
- **frozen_string_literal:** true
- **Begin/rescue/ensure:** Transaction rollback on error, cleanup of _seen markers
- **Input validation:** Network exists, required selections non-empty
- **Nil-safe navigation:** Use of `&.` operator and explicit nil checks
- **Progress logging:** Console puts for long-running operations
- **Visited tracking:** _seen flag to prevent cycles and duplicate processing
- **Cleanup:** Ensure blocks reset temporary markers
