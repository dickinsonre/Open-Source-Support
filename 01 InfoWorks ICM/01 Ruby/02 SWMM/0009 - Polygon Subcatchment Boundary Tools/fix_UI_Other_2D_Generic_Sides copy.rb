# frozen_string_literal: true

# Purpose: Reshape selected polygons (2D mesh/zone types) into regular N-sided polygons
# Inputs: Selected 2D geometry polygons, side count (default 9)
# Outputs: Polygon boundary_array updated
# Type: UI Script (geometry, transactions)
# Hardening: nil-safety, boundary validation, transaction rollback

def generate_polygon_boundary(boundary_array, sides)
  raise "Invalid boundary_array" if boundary_array.nil? || boundary_array.empty?
  raise "Invalid sides (need >= 3)" if sides.nil? || sides < 3

  coords = boundary_array.each_slice(2).to_a
  raise "Boundary has < 2 coords" if coords.length < 2

  min_x = coords.map(&:first).min.to_f
  max_x = coords.map(&:first).max.to_f
  min_y = coords.map(&:last).min.to_f
  max_y = coords.map(&:last).max.to_f

  width = max_x - min_x
  height = max_y - min_y
  center_x = min_x + width / 2.0
  center_y = min_y + height / 2.0

  radius_x = width / 2.0
  radius_y = height / 2.0

  polygon_boundary = []
  sides.times do |i|
    angle = 2.0 * Math::PI / sides.to_f * i.to_f
    x = center_x + radius_x * Math.cos(angle)
    y = center_y + radius_y * Math.sin(angle)
    polygon_boundary << x << y
  end

  polygon_boundary << polygon_boundary[0] << polygon_boundary[1]
  polygon_boundary
end

begin
  net = WSApplication.current_network
  raise "Network is nil" if net.nil?

  puts "[#{Time.now.strftime('%H:%M:%S')}] Starting 2D polygon reshaping"

  net.transaction_begin

  polygon_types = [
    'hw_2d_zone', 'hw_2d_ic_polygon', 'hw_2d_point_source', 'hw_2d_boundary_line',
    'hw_2d_bridge', 'hw_2d_line_source', 'hw_2d_results_polygon', 'hw_2d_results_line'
  ]

  sides = 9
  total_reshaped = 0

  polygon_types.each do |polygon_type|
    begin
      net.row_object_collection(polygon_type)&.each do |polygon|
        next if polygon.nil? || !polygon.selected?

        boundary_array = polygon.boundary_array
        next if boundary_array.nil? || boundary_array.empty?

        new_boundary = generate_polygon_boundary(boundary_array, sides)
        polygon.boundary_array = new_boundary
        polygon.write
        total_reshaped += 1
      end
    rescue => e
      puts "[#{Time.now.strftime('%H:%M:%S')}] Error: #{polygon_type} - #{e.message}"
    end
  end

  net.transaction_commit
  puts "[#{Time.now.strftime('%H:%M:%S')}] Reshaped #{total_reshaped} 2D polygons"

rescue => e
  begin
    net.transaction_rollback if net
  rescue
    nil
  end
  puts "[#{Time.now.strftime('%H:%M:%S')}] Error: #{e.message}"
ensure
  puts "[#{Time.now.strftime('%H:%M:%S')}] Script ended"
end
