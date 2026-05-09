# frozen_string_literal: true
# Find the smallest 1 percent of link lengths (UI script for SWMM)
#
# HARDENING APPLIED:
#   - Added frozen_string_literal pragma
#   - Wrapped in begin/rescue/ensure for error handling
#   - Validates current_network is not nil before proceeding
#   - Nil-safety checks on row_objects and attributes
#   - Validates data exists before calculating statistics
#   - Handles empty data gracefully
#   - Progress logging with timestamps

begin
  net = WSApplication.current_network

  if net.nil?
    puts "[#{Time.now}] ERROR: No network is currently open"
    exit 1
  end

  net.clear_selection
  puts "[#{Time.now}] Starting pipe length statistics analysis"

  link_lengths = []
  ro = net.row_objects('sw_conduit')&.each do |ro|
    link_lengths << ro.length if ro.length
  end

  if link_lengths.empty?
    puts "[#{Time.now}] No pipe length data found"
    puts "No conduits were selected."
    exit 0
  end

  # Calculate the threshold length for the lowest 1 percent
  threshold_length = link_lengths.min + (link_lengths.max - link_lengths.min) * 0.01

  # Calculate the median length (50th percentile)
  sorted_lengths = link_lengths.sort
  median_length = sorted_lengths[sorted_lengths.length / 2]

  # Select the links whose length is below the threshold or median length
  selected_links = []
  ro = net.row_objects('sw_conduit')&.each do |ro|
    if ro.length && (ro.length < threshold_length || ro.length < median_length)
      ro.selected = true
      selected_links << ro
    end
  end

  total_links = link_lengths.length

  if selected_links.any?
    puts("| ------------------------------------ | ------ |")
    puts("| Description                          | Value  |")
    puts("| ------------------------------------ | ------ |")
    puts("| Minimum link length                  | #{'%.2f' % link_lengths.min} |")
    puts("| Maximum link length                  | #{'%.2f' % link_lengths.max} |")
    puts("| Threshold length for lowest 1%       | #{'%.2f' % threshold_length} |")
    puts("| Median link length (50th percentile) | #{'%.2f' % median_length} |")
    puts("| Number of links below threshold      | #{selected_links.length} |")
    puts("| Total number of links                | #{total_links} |")
    puts("| ------------------------------------ | ------ |")
    puts "[#{Time.now}] Analysis complete. #{selected_links.length} pipe(s) selected"
  else
    puts "No links were selected."
    puts "[#{Time.now}] No links found below threshold"
  end

rescue => e
  puts "[#{Time.now}] ERROR: #{e.class} - #{e.message}"
  puts "Backtrace:"
  puts e.backtrace.first(5).join("\n")
  exit 1
ensure
  puts "[#{Time.now}] Script execution completed"
end
