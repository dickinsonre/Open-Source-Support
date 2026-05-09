# frozen_string_literal: true
# Find the smallest 10 percent of conduit heights and widths (InfoWorks)
#
# HARDENING APPLIED:
#   - Added frozen_string_literal pragma
#   - Wrapped in begin/rescue/ensure for error handling
#   - Validates current_network is not nil
#   - Nil-safety checks on all attributes
#   - Validates data before statistics calculation
#   - Handles empty data gracefully

begin
  net = WSApplication.current_network

  if net.nil?
    puts "[#{Time.now}] ERROR: No network is currently open"
    exit 1
  end

  net.clear_selection
  puts "[#{Time.now}] Starting conduit parameter statistics"

  conduit_heights = []
  conduit_widths = []
  net.row_objects('hw_conduit')&.each do |ro|
    conduit_heights << ro.conduit_height if ro.conduit_height
    conduit_widths << ro.conduit_width if ro.conduit_width
  end

  if conduit_heights.empty? && conduit_widths.empty?
    puts "[#{Time.now}] No conduit data found"
    puts "No conduits were selected."
    exit 0
  end

  # Calculate the threshold height and width for the lowest ten percent
  threshold_height = conduit_heights.any? ? conduit_heights.min + (conduit_heights.max - conduit_heights.min) * 0.1 : 0
  threshold_width = conduit_widths.any? ? conduit_widths.min + (conduit_widths.max - conduit_widths.min) * 0.1 : 0

  # Calculate the median height and width (50th percentile)
  sorted_heights = conduit_heights.sort
  median_height = conduit_heights.any? ? sorted_heights[sorted_heights.length / 2] : 0
  sorted_widths = conduit_widths.sort
  median_width = conduit_widths.any? ? sorted_widths[sorted_widths.length / 2] : 0

  # Select the conduits whose height or width is below the threshold or median
  selected_conduits = []
  net.row_objects('hw_conduit')&.each do |ro|
    if (ro.conduit_height && (ro.conduit_height < threshold_height || ro.conduit_height < median_height)) ||
       (ro.conduit_width && (ro.conduit_width < threshold_width || ro.conduit_width < median_width))
      ro.selected = true
      selected_conduits << ro
    end
  end

  total_conduits = [conduit_heights.length, conduit_widths.length].max

  if selected_conduits.any?
    printf("%-44s %-0.2f\n", "Minimum conduit height", conduit_heights.min) if conduit_heights.any?
    printf("%-44s %-0.2f\n", "Maximum conduit height", conduit_heights.max) if conduit_heights.any?
    printf("%-44s %-0.2f\n", "Threshold height for lowest 10%", threshold_height) if conduit_heights.any?
    printf("%-44s %-0.2f\n", "Median conduit height (50th percentile)", median_height) if conduit_heights.any?
    printf("%-44s %-0.2f\n", "Minimum conduit width", conduit_widths.min) if conduit_widths.any?
    printf("%-44s %-0.2f\n", "Maximum conduit width", conduit_widths.max) if conduit_widths.any?
    printf("%-44s %-0.2f\n", "Threshold width for lowest 10%", threshold_width) if conduit_widths.any?
    printf("%-44s %-0.2f\n", "Median conduit width (50th percentile)", median_width) if conduit_widths.any?
    printf("%-44s %-d\n", "Number of conduits below threshold", selected_conduits.length)
    printf("%-44s %-d\n", "Total number of conduits", total_conduits)
    puts "[#{Time.now}] Analysis complete. #{selected_conduits.length} conduit(s) selected"
  else
    puts "No conduits were selected."
    puts "[#{Time.now}] No conduits found below threshold"
  end

rescue => e
  puts "[#{Time.now}] ERROR: #{e.class} - #{e.message}"
  puts "Backtrace:"
  puts e.backtrace.first(5).join("\n")
  exit 1
ensure
  puts "[#{Time.now}] Script execution completed"
end
