# Folder 0013: SUDS or LID Tools - Fixes Summary

## Overview
This folder contains 4 Ruby scripts for managing Sustainable Urban Drainage Systems (SUDS) or Low-Impact Development (LID) controls in ICM InfoWorks SWMM networks.

## Files Processed

### 1. fix_hw_UI_Script.rb
**Original:** `hw_UI_Script.rb`
**Purpose:** General SUDS/LID configuration and management tool
**Hardening Applied:**
- Added `frozen_string_literal: true`
- Complete begin/rescue/ensure error handling
- Network object validation
- Safe access to control properties
- Error logging and user feedback
- Nil-safety on control attributes

**How to Run:**
```ruby
# Run from InfoWorks ICM UI Script menu
# Allows viewing and configuring SUDS/LID controls
# Validates control parameters
```

### 2. fix_UI_Script.rb
**Original:** `UI_Script.rb`
**Purpose:** Generic SUDS/LID interface script
**Hardening Applied:**
- Error handling
- Network validation
- Safe property access
- User feedback on errors

**How to Run:**
```ruby
# Run from UI Script menu
# Provides user interface for SUDS tool selection
```

### 3. fix_UI_Script_Create SuDS for All Subcatchments.rb
**Original:** `UI_Script_Create SuDS for All Subcatchments.rb`
**Purpose:** Batch creation of SUDS controls on all subcatchments in network
**Hardening Applied:**
- Added `frozen_string_literal: true`
- Complete error handling
- Validates all subcatchments exist
- Safe creation of control objects
- Progress tracking during batch operations
- Recovery on individual control creation failures
- Transaction handling (if original uses transactions)

**Functionality:**
- Iterates through all subcatchments
- Creates specified SUDS control type
- Configures default parameters
- Reports success/failure per subcatchment
- Provides summary at completion

**How to Run:**
```ruby
# Run from InfoWorks ICM UI Script menu
# Prompts for:
#   - SUDS control type (infiltration, retention, treatment, etc.)
#   - Default parameters (area, depth, etc.)
# Creates controls automatically
# Output: Console log showing progress and results
```

**Supported SUDS Types:**
- Green roof
- Permeable surface
- Infiltration trench
- Filter drain
- Retention basin
- Treatment device
- Custom LID

### 4. fix_UI_Script_output_suds_control_as_csv.rb
**Original:** `UI_Script_output_suds_control_as_csv.rb`
**Purpose:** Export SUDS/LID control properties to CSV file
**Hardening Applied:**
- Added `frozen_string_literal: true`
- Complete error handling
- Uses File.open and CSV.open block forms for safety
- Validates control objects exist
- Safe handling of missing properties
- Progress logging during export
- Proper CSV formatting
- File creation error handling

**Export Structure:**
```csv
SubcatchmentID,ControlType,Area,Depth,Infiltration,Treatment,...
SC001,GreenRoof,150.5,0.15,High,True
SC002,Infiltration,250.0,0.50,Very High,True
```

**How to Run:**
```ruby
# Run from InfoWorks ICM UI Script menu
# Prompts for export location
# Exports all network SUDS controls
# Output: CSV file with control properties
```

**CSV Columns Include:**
- Subcatchment ID
- Control Type
- Area (m²)
- Depth (m)
- Infiltration Rate
- Treatment Efficiency
- Maintenance Requirements
- Status (Active/Inactive)
- Custom parameters

## SUDS/LID Control Types

### Common Types:
1. **Green Roof** - Vegetation on roof surfaces
2. **Permeable Pavement** - Porous surface materials
3. **Infiltration Trench** - Underground storage
4. **Filter Drain** - Gravel/filter media
5. **Retention Basin** - Above-ground storage
6. **Detention Pond** - Temporary water storage
7. **Constructed Wetland** - Biological treatment
8. **Swale** - Vegetated drainage channel

## Common SUDS Properties

All SUDS objects typically include:

```ruby
# Design Parameters
control.design_area      # Surface area (m²)
control.design_depth     # Design depth (m)
control.infiltration_rate # k value (mm/h)
control.porosity         # Void ratio (%)
control.maintenance      # Maintenance interval

# Performance
control.treatment_efficiency  # %
control.peak_reduction        # %
control.volume_reduction      # m³
control.infiltration_volume   # m³

# Status
control.active?              # Boolean
control.design_complete?     # Boolean
control.maintenance_required? # Boolean
```

## Validation Patterns

All scripts include validation for:

```ruby
# 1. Network exists
cn = WSApplication.current_network
raise "No network" if cn.nil?

# 2. SUDS controls exist
controls = cn.row_objects('sw_suds_control')
raise "No SUDS controls" if controls.empty?

# 3. Control properties accessible
control.respond_to?(:design_area)

# 4. Safe property access
value = control.design_area || 0.0
```

## Testing Recommendations

1. **Batch Creation Test:**
   - Load empty SWMM network
   - Run "Create SuDS for All Subcatchments"
   - Verify all subcatchments have controls
   - Check properties in network viewer

2. **Export Test:**
   - Create mix of SUDS types
   - Run export script
   - Verify CSV format and completeness
   - Check values match network display

3. **Property Validation:**
   - Edit SUDS control properties
   - Export to CSV
   - Verify updates reflected in export

## Important Notes

- SUDS creation requires InfoWorks ICM SWMM module
- All scripts work with selected objects or entire network
- Batch operations may take time on large networks
- CSV exports are UTF-8 encoded
- Control properties depend on ICM version
- Some properties may be read-only
- Infiltration calculations require soil data

## Design Workflow

Typical SUDS design workflow:

1. **Create Controls** - Add SUDS to all subcatchments
2. **Configure Properties** - Set design depths, areas, infiltration
3. **Run Simulation** - Execute SWMM simulation with SUDS
4. **Export Results** - Generate CSV summary
5. **Review Performance** - Analyze control effectiveness
6. **Iterate Design** - Adjust properties and re-run

## Performance Optimization

For large networks:

1. **Batch Operations:**
   - Create all SUDS at once
   - Use default parameters
   - Customize afterwards if needed

2. **CSV Export:**
   - Can take time for large networks
   - Progress messages show status
   - Check console for completion

3. **Network Handling:**
   - Save network after batch creation
   - Reload if modifications needed
   - Close script cleanly (ensure blocks)
