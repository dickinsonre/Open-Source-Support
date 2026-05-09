# frozen_string_literal: true

# Purpose: Create centroid + vertex nodes from selected polygon boundaries
# Inputs: Selected hw_2d_infiltration_zone polygons
# Outputs: hw_node objects at polygon centroid and all vertices
# Type: UI Script (transaction, polygon geometry, boundary_array, centroid calc)
# Hardening: frozen strings, begin/rescue/ensure, boundary validation, zero-guard on division

begin
  net = WSApplication.current_network
  raise "Network is nil" if net.nil?

  puts "[#{Time.now.strftime('%H:%M:%S')}] Starting node creation from polygon boundaries"

  net.transaction_begin

  total_nodes_created = 0

  net.row_object_collection('hw_2d_infiltration_zone')&.each do |polygon|
    begin
      next if polygon.nil?

      puts "Processing polygon: #{polygon.id}"

      next unless polygon.selected?

      boundary_array = polygon.boundary_array
      next if boundary_array.nil? || boundary_array.empty?

      coords = boundary_array.each_slice(2).to_a
      raise "Boundary has < 2 coordinates" if coords.length < 2

      sum_x = coords.map(&:first).sum.to_f
      sum_y = coords.map(&:last).sum.to_f
      coord_count = coords.length.to_f

      raise "Zero coordinates" if coord_count <= 0

      centroid_x = sum_x / coord_count
      centroid_y = sum_y / coord_count

      centroid_node = net.new_row_object('hw_node')
      raise "Failed to create centroid node" if centroid_node.nil?

      centroid_node['node_id'] = "#{polygon.id}_centroid"
      centroid_node['x'] = centroid_x
      centroid_node['y'] = centroid_y
      centroid_node.write
      total_nodes_created += 1

      boundary_array.each_slice(2).with_index do |(x, y), index|
        next if x.nil? || y.nil?

        vertex_node = net.new_row_object('hw_node')
        raise "Failed to create vertex node" if vertex_node.nil?

        vertex_node['node_id'] = "#{polygon.id}_vertex_#{index}"
        vertex_node['x'] = x
        vertex_node['y'] = y
        vertex_node.write
        total_nodes_created += 1
      end

      puts "[#{Time.now.strftime('%H:%M:%S')}] Created #{coords.length + 1} nodes (1 centroid + #{coords.length} vertices) for polygon #{polygon.id}"
    rescue => e
      puts "[#{Time.now.strftime('%H:%M:%S')}] Error processing polygon #{polygon.id}: #{e.message}"
    end
  end

  net.transaction_commit
  puts "[#{Time.now.strftime('%H:%M:%S')}] Completed: created #{total_nodes_created} total nodes"

rescue => e
  begin
    net.transaction_rollback if net
  rescue
    nil
  end
  puts "[#{Time.now.strftime('%H:%M:%S')}] Fatal error: #{e.message}"
  puts e.backtrace.first(5)
ensure
  puts "[#{Time.now.strftime('%H:%M:%S')}] Script ended"
end
