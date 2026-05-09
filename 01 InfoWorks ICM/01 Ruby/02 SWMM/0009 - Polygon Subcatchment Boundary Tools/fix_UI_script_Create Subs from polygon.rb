# frozen_string_literal: true

# Purpose: Create subcatchments from polygon boundaries
# Inputs: Selected polygons
# Outputs: hw_subcatchment objects created from polygon geometry
# Type: UI Script (transaction, polygon geometry)
# Hardening: frozen strings, begin/rescue/ensure, boundary validation, transaction guard

begin
  net = WSApplication.current_network
  raise "Network is nil" if net.nil?

  puts "[#{Time.now.strftime('%H:%M:%S')}] Starting subcatchment creation from polygons"

  net.transaction_begin

  total_subs = 0

  polygon_types = [
    'hw_2d_infiltration_zone', 'hw_2d_permeable_zone', 'hw_mesh_zone',
    'hw_2d_results_polygon', 'hw_roughness_zone', 'hw_porous_polygon', 'hw_polygon'
  ]

  polygon_types.each do |polygon_type|
    begin
      net.row_object_collection(polygon_type)&.each do |polygon|
        next if polygon.nil? || !polygon.selected?

        boundary_array = polygon.boundary_array
        next if boundary_array.nil? || boundary_array.empty?

        sub = net.new_row_object('hw_subcatchment')
        raise "Failed to create subcatchment" if sub.nil?

        sub['subcatchment_id'] = "Sub_#{polygon.id}"
        sub.geometry = boundary_array
        sub.write

        total_subs += 1
        puts "[#{Time.now.strftime('%H:%M:%S')}] Created subcatchment from polygon #{polygon.id}"
      end
    rescue => e
      puts "[#{Time.now.strftime('%H:%M:%S')}] Error processing polygon type #{polygon_type}: #{e.message}"
    end
  end

  net.transaction_commit
  puts "[#{Time.now.strftime('%H:%M:%S')}] Completed: created #{total_subs} subcatchments"

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
