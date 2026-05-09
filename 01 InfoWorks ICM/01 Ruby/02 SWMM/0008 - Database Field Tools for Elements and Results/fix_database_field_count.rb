# frozen_string_literal: true

# Purpose: Find network elements and format ID output in columns
# Inputs: Network, object types (hw_sim_parameters, hw_node, hw_conduit, etc.)
# Outputs: Formatted console table with element IDs grouped by type
# Type: EX Script (network.row_objects, respond_to checks)
# Hardening: nil-safety, respond_to? checks, id fallback chain, sorting/slicing

begin
  net = WSApplication.current_network
  raise "Network is nil" if net.nil?

  def get_network_elements_with_ids(network, object_type)
    return nil if network.nil?
    elements = network.row_objects(object_type)
    return nil if elements.nil?

    ids = []
    elements&.each do |element|
      next if element.nil?
      id = nil
      if element.respond_to?(:id)
        id = element.id
      elsif element.respond_to?(:us_node_id)
        id = element.us_node_id
      elsif element.respond_to?(:node_id)
        id = element.node_id
      elsif element.respond_to?(:link_id)
        id = element.link_id
      elsif element.respond_to?(:name)
        id = element.name
      elsif element.respond_to?(:descriptor)
        id = element.descriptor
      end
      ids << (id || "Unknown ID")
    end
    ids
  end

  def format_table_output(table_name, ids)
    output = "\n#{table_name.split('_').map(&:capitalize).join(' ')} (Count: #{ids.length}):\n"
    output += "-" * 80 + "\n"

    if ids.length > 0
      sorted_ids = ids.sort rescue ids
      sorted_ids&.each_slice(5)&.with_index do |row_ids, row_index|
        row_output = ""
        row_ids&.each_with_index do |id, col_index|
          item_number = row_index * 5 + col_index + 1
          row_output += sprintf("%-3d. %-15s", item_number, id.to_s[0..14])
        end
        output += "  #{row_output}\n"
      end
    else
      output += "  No elements found\n"
    end
    output += "\n"
    output
  end

  puts "[#{Time.now.strftime('%H:%M:%S')}] Starting network element enumeration"

  results = "Network Element Parameter IDs:\n"
  results += "=" * 50 + "\n"

  tables = [
    'hw_sim_parameters', 'hw_manhole_defaults', 'hw_conduit_defaults', 'hw_subcatchment_defaults',
    'hw_large_catchment_parameters', 'hw_snow_parameters', 'hw_wq_params', 'hw_node', 'hw_conduit', 'hw_flap_valve',
    'hw_orifice', 'hw_pump', 'hw_sluice', 'hw_user_control', 'hw_weir', 'hw_flume', 'hw_siphon', 'hw_screen', 'hw_channel',
    'hw_channel_defaults', 'hw_river_reach_defaults', 'hw_culvert_inlet', 'hw_culvert_outlet', 'hw_blockage', 'hw_bridge_blockage',
    'hw_shape', 'hw_head_discharge', 'hw_runoff_surface', 'hw_land_use', 'hw_snow_pack', 'hw_headloss', 'hw_ground_infiltration',
    'hw_subcatchment', 'hw_polygon', 'hw_unit_hydrograph', 'hw_unit_hydrograph_month', 'hw_channel_shape', 'hw_general_line',
    'hw_porous_wall', 'hw_2d_zone', 'hw_mesh_zone', 'hw_roughness_zone', 'hw_2d_ic_polygon', 'hw_2d_point_source', 'hw_2d_boundary_line'
  ]

  table_data = []
  tables&.each do |table|
    begin
      ids = get_network_elements_with_ids(net, table)
      if ids && ids.length > 0
        table_data << [table, ids]
      end
    rescue => e
      puts "[#{Time.now.strftime('%H:%M:%S')}] Error processing table #{table}: #{e.message}"
    end
  end

  table_data.sort_by! { |_, ids| -ids.length } rescue nil

  table_data&.each do |table, ids|
    results += format_table_output(table, ids)
  end

  puts results
  puts "[#{Time.now.strftime('%H:%M:%S')}] Completed: processed #{table_data.length} tables with elements"

rescue => e
  puts "[#{Time.now.strftime('%H:%M:%S')}] Fatal error: #{e.message}"
  puts e.backtrace.first(5)
ensure
  puts "[#{Time.now.strftime('%H:%M:%S')}] Script ended"
end
