# frozen_string_literal: true
# Pipe length histogram statistics (InfoWorks)
#
# HARDENING APPLIED:
#   - Added frozen_string_literal pragma
#   - Wrapped in begin/rescue/ensure
#   - Validates network is open
#   - Nil-safety on attributes

begin
  net = WSApplication.current_network
  if net.nil?
    puts "[#{Time.now}] ERROR: No network is currently open"
    exit 1
  end

  net.clear_selection
  puts "[#{Time.now}] Starting pipe length histogram analysis"

  link_lengths = []
  net.row_objects('hw_conduit')&.each do |ro|
    link_lengths << ro.conduit_length if ro.conduit_length
  end

  if link_lengths.empty?
    puts "[#{Time.now}] No conduit data found"
    puts "No links were selected."
    exit 0
  end

  threshold_length = link_lengths.min + (link_lengths.max - link_lengths.min) * 0.1
  sorted_lengths = link_lengths.sort
  median_length = sorted_lengths[sorted_lengths.length / 2]

  selected_links = []
  net.row_objects('hw_conduit')&.each do |ro|
    if ro.conduit_length && (ro.conduit_length < threshold_length || ro.conduit_length < median_length)
      ro.selected = true
      selected_links << ro
    end
  end

  total_links = link_lengths.length

  if selected_links.any?
    printf("%-50s %12.2f\n", "Minimum link length", link_lengths.min)
    printf("%-50s %12.2f\n", "Maximum link length", link_lengths.max)
    printf("%-50s %12.2f\n", "Threshold length for lowest 10%", threshold_length)
    printf("%-50s %12.2f\n", "Median link length (50th percentile)", median_length)
    printf("%-50s %12d\n", "Number of links below threshold", selected_links.length)
    printf("%-50s %12d\n", "Total number of links", total_links)
    puts "[#{Time.now}] Analysis complete. #{selected_links.length} link(s) selected"
  else
    puts "No links were selected."
    puts "[#{Time.now}] No links found below threshold"
  end

rescue => e
  puts "[#{Time.now}] ERROR: #{e.class} - #{e.message}"
  exit 1
ensure
  puts "[#{Time.now}] Script execution completed"
end
