# frozen_string_literal: true

# Purpose: Generate grid result points inside selected 2D mesh/infiltration/permeable polygons
# Inputs: Selected polygons (hw_2d_infiltration_zone, hw_2d_permeable_zone, etc.), point count (100)
# Outputs: hw_2d_results_point objects created within polygon bounds
# Type: UI Script (transaction, polygon.boundary_array, geometry)
# Hardening: frozen strings, begin/rescue/ensure, nil-safety, boundary validation, transaction guard

def generate_polygon_1d_results(boundary_array, points, polygon_id, net)
  raise "Invalid boundary_array" if boundary_array.nil? || boundary_array.empty?
  raise "Invalid points count" if points.nil? || points <= 0
  raise "Network is nil" if net.nil?

  coords = boundary_array.each_slice(2).to_a
  raise "Boundary has < 2 coordinates" if coords.length < 2

  min_x = coords.map(&:first).min.to_f
  max_x = coords.map(&:first).max.to_f
  min_y = coords.map(&:last).min.to_f
  max_y = coords.map(&:last).max.to_f

  width = max_x - min_x
  height = max_y - min_y

  raise "Invalid polygon extent: width=#{width}, height=#{height}" if width <= 0 || height <= 0

  x_step = width / ([points - 1, 1].max).to_f
  y_step = height / ([points - 1, 1].max).to_f

  polygon_points = []
  point_id = 0
  points.times do |i|
    points.times do |j|
      x = min_x + i * x_step
      y = min_y + j * y_step
      point_id += 1

      point = net.new_row_object('hw_2d_results_point')
      raise "Failed to create result point" if point.nil?

      point['point_id'] = "#{polygon_id}_#{point_id}"
      point['point_x'] = x
      point['point_y'] = y
      point.write
      polygon_points << point
    end
  end

  polygon_points
end

begin
  net = WSApplication.current_network
  raise "Network is nil" if net.nil?

  puts "[#{Time.now.strftime('%H:%M:%S')}] Starting polygon result point generation"

  net.transaction_begin

  polygon_types = [
    'hw_2d_infiltration_zone', 'hw_2d_permeable_zone', 'hw_mesh_zone',
    'hw_2d_results_polygon', 'hw_roughness_zone', 'hw_porous_polygon', 'hw_polygon'
  ]

  total_points_created = 0
  polygon_types.each do |polygon_type|
    begin
      net.row_object_collection(polygon_type)&.each do |polygon|
        next if polygon.nil? || !polygon.selected?

        boundary_array = polygon.boundary_array
        next if boundary_array.nil? || boundary_array.empty?

        points = generate_polygon_1d_results(boundary_array, 100, polygon.id, net)
        total_points_created += points.length if points
        puts "[#{Time.now.strftime('%H:%M:%S')}] Created #{points&.length || 0} points for polygon #{polygon.id}"
      end
    rescue => e
      puts "[#{Time.now.strftime('%H:%M:%S')}] Error processing polygon type #{polygon_type}: #{e.message}"
    end
  end

  net.transaction_commit
  puts "[#{Time.now.strftime('%H:%M:%S')}] Completed: created #{total_points_created} total result points"

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
