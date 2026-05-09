# frozen_string_literal: true
# ---------------------------------------------------------------------------
# fix_ICM SWMM Network Overview.rb
#
# Purpose : High-level summary of an ICM SWMM network - counts of nodes
#           (junction/storage/outfall), conduits, subcatchments, pumps,
#           weirs, orifices and outlets, plus mean/min/max stats for key
#           geometric and hydraulic attributes.
# Inputs  : Active ICM SWMM current_network.
# Outputs : Console summary table.
# Type    : UI script.
# Hardening:
#   * frozen_string_literal pragma
#   * Validates current_network and each row_objects() call
#   * Guards against zero-division when no rows exist
#   * Nil-safe attribute access via &.
#   * begin/rescue/ensure around main logic
#   * Timestamped logging
# Source  : https://github.com/chaitanyalakeshri/ruby_scripts
# ---------------------------------------------------------------------------

def log(msg)
  puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] #{msg}"
end

begin
  net = WSApplication.current_network
  raise 'Error: current network not found' if net.nil?

  log 'Loading row object collections...'
  nodes_ro = net.row_objects('sw_node')
  raise 'Error: nodes not found' if nodes_ro.nil?

  number_nodes = 0
  number_outfalls = 0
  number_storage = 0
  number_junction = 0
  number_inflow_baseline = 0
  number_inflow_scaling = 0
  number_base_flow = 0
  number_additional_dwf = 0

  total_invert = 0.0; max_invert = -Float::MAX; min_invert = Float::MAX
  total_ground = 0.0; max_ground = -Float::MAX; min_ground = Float::MAX
  total_depth = 0.0; max_depth = -Float::MAX; min_depth = Float::MAX
  total_initial_depth = 0.0; max_initial_depth = -Float::MAX; min_initial_depth = Float::MAX
  total_surcharge_depth = 0.0; max_surcharge_depth = -Float::MAX; min_surcharge_depth = Float::MAX
  total_ponded_area = 0.0; max_ponded_area = -Float::MAX; min_ponded_area = Float::MAX

  nodes_ro.each do |node|
    next if node.nil?

    (node.additional_dwf || []).each do |adwf|
      number_additional_dwf += 1 if adwf&.baseline && adwf.baseline > 0
    end

    number_inflow_scaling  += 1 if node.inflow_scaling && node.inflow_scaling > 0
    number_base_flow       += 1 if node.base_flow && node.base_flow > 0
    number_inflow_baseline += 1 if node.inflow_baseline && node.inflow_baseline > 0
    number_nodes += 1

    case node.node_type
    when 'Outfall'  then number_outfalls += 1
    when 'Storage'  then number_storage  += 1
    when 'Junction' then number_junction += 1
    end

    if node.invert_elevation
      total_invert += node.invert_elevation
      max_invert = node.invert_elevation if node.invert_elevation > max_invert
      min_invert = node.invert_elevation if node.invert_elevation < min_invert
    end
    if node.ground_level
      total_ground += node.ground_level
      max_ground = node.ground_level if node.ground_level > max_ground
      min_ground = node.ground_level if node.ground_level < min_ground
    end
    if node.maximum_depth
      total_depth += node.maximum_depth
      max_depth = node.maximum_depth if node.maximum_depth > max_depth
      min_depth = node.maximum_depth if node.maximum_depth < min_depth
    end
    if node.initial_depth
      total_initial_depth += node.initial_depth
      max_initial_depth = node.initial_depth if node.initial_depth > max_initial_depth
      min_initial_depth = node.initial_depth if node.initial_depth < min_initial_depth
    end
    if node.surcharge_depth
      total_surcharge_depth += node.surcharge_depth
      max_surcharge_depth = node.surcharge_depth if node.surcharge_depth > max_surcharge_depth
      min_surcharge_depth = node.surcharge_depth if node.surcharge_depth < min_surcharge_depth
    end
    if node.ponded_area
      total_ponded_area += node.ponded_area
      max_ponded_area = node.ponded_area if node.ponded_area > max_ponded_area
      min_ponded_area = node.ponded_area if node.ponded_area < min_ponded_area
    end
  end

  if number_nodes.positive?
    mean_invert = total_invert / number_nodes
    mean_ground = total_ground / number_nodes
    mean_depth = total_depth / number_nodes
    mean_initial_depth = total_initial_depth / number_nodes
    mean_surcharge_depth = total_surcharge_depth / number_nodes
    mean_ponded_area = total_ponded_area / number_nodes

    printf "%-40s %-d\n", 'Number of SW Nodes', number_nodes
    printf "%-40s %-d\n", 'Number of SW Junctions', number_junction
    printf "%-40s %-d\n", 'Number of SW Storage', number_storage
    printf "%-40s %-d\n", 'Number of SW Outfalls', number_outfalls
    printf "%-40s %-d\n", 'Number of SW Inflow Baseline', number_inflow_baseline
    printf "%-40s %-d\n", 'Number of SW Inflow Scaling', number_inflow_scaling
    printf "%-40s %-d\n", 'Number of SW Base Flow', number_base_flow
    printf "%-40s %-d\n", 'Number_of_additional_dwf', number_additional_dwf
    printf "%-40s %-20s %-20s %-20s\n", '', 'Mean', 'Max', 'Min'
    printf "%-40s %-20.3f %-20.3f %-20.3f\n", 'Invert Elevation', mean_invert, max_invert, min_invert
    printf "%-40s %-20.3f %-20.3f %-20.3f\n", 'Ground Elevation', mean_ground, max_ground, min_ground
    printf "%-40s %-20.3f %-20.3f %-20.3f\n", 'Full Depth', mean_depth, max_depth, min_depth
    printf "%-40s %-20.3f %-20.3f %-20.3f\n", 'Initial Depth', mean_initial_depth, max_initial_depth, min_initial_depth
    printf "%-40s %-20.3f %-20.3f %-20.3f\n", 'Surcharge Depth', mean_surcharge_depth, max_surcharge_depth, min_surcharge_depth
    printf "%-40s %-20.3f %-20.3f %-20.3f\n", 'Ponded Area', mean_ponded_area, max_ponded_area, min_ponded_area
  else
    log 'No sw_node rows; skipping node stats.'
  end

  links_ro = net.row_objects('sw_conduit')
  raise 'Error: links not found' if links_ro.nil?

  number_links = 0
  number_length = 0.0
  total_conduit_height = 0.0; max_conduit_height = -Float::MAX; min_conduit_height = Float::MAX
  total_conduit_width = 0.0;  max_conduit_width = -Float::MAX;  min_conduit_width = Float::MAX
  total_manning_n = 0.0;      max_manning_n = -Float::MAX;      min_manning_n = Float::MAX
  total_downstream_invert = 0.0; max_downstream_invert = -Float::MAX; min_downstream_invert = Float::MAX
  total_upstream_invert = 0.0;   max_upstream_invert = -Float::MAX;   min_upstream_invert = Float::MAX
  total_number_of_barrels = 0;   max_number_of_barrels = -Float::MAX; min_number_of_barrels = Float::MAX

  links_ro.each do |link|
    next if link.nil?
    number_links += 1
    number_length += link.length.to_f
    if link.Conduit_height
      total_conduit_height += link.Conduit_height
      max_conduit_height = link.Conduit_height if link.Conduit_height > max_conduit_height
      min_conduit_height = link.Conduit_height if link.Conduit_height < min_conduit_height
    end
    if link.Conduit_width
      total_conduit_width += link.Conduit_width
      max_conduit_width = link.Conduit_width if link.Conduit_width > max_conduit_width
      min_conduit_width = link.Conduit_width if link.Conduit_width < min_conduit_width
    end
    if link.Mannings_N
      total_manning_n += link.Mannings_N
      max_manning_n = link.Mannings_N if link.Mannings_N > max_manning_n
      min_manning_n = link.Mannings_N if link.Mannings_N < min_manning_n
    end
    if link.ds_invert
      total_downstream_invert += link.ds_invert
      max_downstream_invert = link.ds_invert if link.ds_invert > max_downstream_invert
      min_downstream_invert = link.ds_invert if link.ds_invert < min_downstream_invert
    end
    if link.us_invert
      total_upstream_invert += link.us_invert
      max_upstream_invert = link.us_invert if link.us_invert > max_upstream_invert
      min_upstream_invert = link.us_invert if link.us_invert < min_upstream_invert
    end
    if link.number_of_barrels
      total_number_of_barrels += link.number_of_barrels
      max_number_of_barrels = link.number_of_barrels if link.number_of_barrels > max_number_of_barrels
      min_number_of_barrels = link.number_of_barrels if link.number_of_barrels < min_number_of_barrels
    end
  end

  if number_links.positive?
    printf "%-40s %-d\n", 'Number of SW Links', number_links
    printf "%-40s %-.3f\n", 'Total SW Length', number_length
    printf "%-40s %-20s %-20s %-20s\n", '', 'Mean', 'Max', 'Min'
    printf "%-40s %-20.3f %-20.3f %-20.3f\n", 'Conduit Height', total_conduit_height / number_links, max_conduit_height, min_conduit_height
    printf "%-40s %-20.3f %-20.3f %-20.3f\n", 'Conduit Width', total_conduit_width / number_links, max_conduit_width, min_conduit_width
    printf "%-40s %-20.3f %-20.3f %-20.3f\n", 'Manning n', total_manning_n / number_links, max_manning_n, min_manning_n
    printf "%-40s %-20.3f %-20.3f %-20.3f\n", 'Downstream Invert', total_downstream_invert / number_links, max_downstream_invert, min_downstream_invert
    printf "%-40s %-20.3f %-20.3f %-20.3f\n", 'Upstream Invert', total_upstream_invert / number_links, max_upstream_invert, min_upstream_invert
    printf "%-40s %-20.3f %-20.3f %-20.3f\n", 'Number of Barrels', total_number_of_barrels.to_f / number_links, max_number_of_barrels, min_number_of_barrels
  end

  subcatchments_ro = net.row_objects('sw_subcatchment')
  raise 'Error: subcatchments not found' if subcatchments_ro.nil?

  number_subcatchments = 0
  total_area = 0.0
  total_imperviousness = 0.0; max_imperviousness = -Float::MAX; min_imperviousness = Float::MAX
  total_slope = 0.0; max_slope = -Float::MAX; min_slope = Float::MAX
  total_width = 0.0; max_width = -Float::MAX; min_width = Float::MAX

  subcatchments_ro.each do |sub|
    next if sub.nil?
    number_subcatchments += 1
    total_area += sub.area.to_f if sub.area
    if sub.percent_impervious
      v = sub.percent_impervious.to_f
      total_imperviousness += v
      max_imperviousness = v if v > max_imperviousness
      min_imperviousness = v if v < min_imperviousness
    end
    if sub.catchment_slope
      v = sub.catchment_slope.to_f
      total_slope += v
      max_slope = v if v > max_slope
      min_slope = v if v < min_slope
    end
    if sub.width
      v = sub.width.to_f
      total_width += v
      max_width = v if v > max_width
      min_width = v if v < min_width
    end
  end

  if number_subcatchments.positive?
    printf "%-40s %-d\n", 'Number of SW Subcatchments', number_subcatchments
    printf "%-40s %-.3f\n", 'Total SW Subcatchment Area', total_area
    printf "%-40s %-20s %-20s %-20s\n", '', 'Mean', 'Max', 'Min'
    printf "%-40s %-20.3f %-20.3f %-20.3f\n", 'Imperviousness', total_imperviousness / number_subcatchments, max_imperviousness, min_imperviousness
    printf "%-40s %-20.3f %-20.3f %-20.3f\n", 'Subcatchment Slope', total_slope / number_subcatchments, max_slope, min_slope
    printf "%-40s %-20.3f %-20.3f %-20.3f\n", 'Subcatchment Width', total_width / number_subcatchments, max_width, min_width
  end

  %w[sw_pump sw_weir sw_orifice sw_outlet].each do |tbl|
    rows = net.row_objects(tbl)
    if rows.nil?
      printf "%-40s %-s\n", "Number of #{tbl}", 'N/A'
    else
      n = 0
      rows.each { |_| n += 1 }
      printf "%-40s %-d\n", "Number of #{tbl}", n
    end
  end

  printf "%-40s\n", 'This was an overview of the elements in an ICM SWMM Network'
rescue StandardError => e
  log "Aborted: #{e.message}"
ensure
  log 'fix_ICM SWMM Network Overview.rb finished.'
end
