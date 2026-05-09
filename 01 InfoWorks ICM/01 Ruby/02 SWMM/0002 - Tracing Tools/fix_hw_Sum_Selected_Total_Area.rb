# frozen_string_literal: true

# Purpose: Calculate total area of selected InfoWorks subcatchments with count
# Inputs: UI script; requires subcatchment selection
# Outputs: Prints total area, count, and zero-area warning if applicable
# Type: UI script (runs in ICM context)
# Hardening: Begin/rescue/ensure, nil checks

def calculate_total_area(net)
  raise 'Network is not open' if net.nil?

  total_area = 0
  count = 0

  net.row_object_collection('hw_subcatchment').each do |s|
    if s.selected?
      total_area += s.total_area
      count += 1
    end
  end

  puts "Total Area: #{'%.3f' % total_area}"
  puts "Number of selected subcatchments: #{count}"

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

rescue => e
  puts "Error calculating total area: #{e.message}"
  WSApplication.message_box("Error: #{e.message}", 'OK', '!', false)
ensure
  # Cleanup if needed
end
