# frozen_string_literal: true

# Purpose: Calculate total area of selected InfoWorks subcatchments
# Inputs: UI script; requires subcatchment selection
# Outputs: Prints total area, count, and zero-area message if applicable
# Type: UI script (runs in ICM context)
# Hardening: Begin/rescue/ensure, nil checks, fixed syntax errors

def calculate_total_area(net)
  raise 'Network is not open' if net.nil?

  total_area = 0

  net.row_object_collection('hw_subcatchment').each do |s|
    total_area += s.total_area if s.selected?
  end

  puts "Total Area: #{total_area.round(3)}"
  if total_area == 0
    puts 'Either you selected no subcatchments or you have no subcatchments with a non-zero area.'
  end

  total_area
end

begin
  net = WSApplication.current_network
  raise 'Network is not open' if net.nil?

  # Call the method to calculate and print the total area
  calculate_total_area(net)
  puts 'Thank you for using Ruby in ICM InfoWorks'

  # Count and display total subcatchments in network
  subcatchments = net.row_objects('hw_subcatchment')
  puts "Total subcatchments in network: #{subcatchments.length}"

rescue => e
  puts "Error calculating total area: #{e.message}"
  WSApplication.message_box("Error: #{e.message}", 'OK', '!', false)
ensure
  # Cleanup if needed
end
