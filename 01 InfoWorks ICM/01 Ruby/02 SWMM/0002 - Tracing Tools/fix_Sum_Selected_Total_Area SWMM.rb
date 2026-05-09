# frozen_string_literal: true

# Purpose: Calculate total area of selected SWMM subcatchments
# Inputs: UI script; requires subcatchment selection
# Outputs: Prints total area and count; message box confirmation
# Type: UI script (runs in ICM context)
# Hardening: Begin/rescue/ensure, nil checks, validation

def calculate_total_selected_subcatchment_area(net)
  raise 'Network is not open' if net.nil?

  total_area = 0
  count = 0

  net.row_object_collection('sw_subcatchment').each do |subcatchment|
    total_area += subcatchment.area if subcatchment.selected?
    count += 1 if subcatchment.selected?
  end

  [total_area, count]
end

def print_total_area(net)
  total_area, count = calculate_total_selected_subcatchment_area(net)

  puts "Total Area: #{total_area.round(3)}"
  puts "Number of selected subcatchments: #{count}"
  puts 'Thank you for using Ruby in ICM SWMM'

  all_subs = net.row_objects('sw_subcatchment')
  puts "Total subcatchments in network: #{all_subs.length}"

  total_area
end

begin
  net = WSApplication.current_network
  raise 'Network is not open' if net.nil?

  total = print_total_area(net)

  WSApplication.message_box(
    "Total selected area: #{total.round(3)}\nThank you for using Ruby in ICM SWMM",
    'OK',
    '?',
    false
  )
rescue => e
  puts "Error calculating total area: #{e.message}"
  WSApplication.message_box("Error: #{e.message}", 'OK', '!', false)
ensure
  # Cleanup if needed
end
