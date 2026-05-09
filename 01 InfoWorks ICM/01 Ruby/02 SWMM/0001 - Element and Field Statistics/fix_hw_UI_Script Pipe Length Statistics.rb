# frozen_string_literal: true
# Pipe length statistics (InfoWorks)
begin
  net = WSApplication.current_network
  exit 1 if net.nil?

  net.clear_selection
  link_lengths = []
  net.row_objects('hw_conduit')&.each { |ro| link_lengths << ro.conduit_length if ro.conduit_length }

  if link_lengths.empty?
    puts "No conduits were selected."
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

  if selected_links.any?
    puts("| ------------------------------------ | ------ |")
    puts("| Description                          | Value  |")
    puts("| ------------------------------------ | ------ |")
    puts("| Minimum link length                  | #{'%.2f' % link_lengths.min} |")
    puts("| Maximum link length                  | #{'%.2f' % link_lengths.max} |")
    puts("| Threshold length for lowest 10%      | #{'%.2f' % threshold_length} |")
    puts("| Median link length (50th percentile) | #{'%.2f' % median_length} |")
    puts("| Number of links below threshold      | #{selected_links.length} |")
    puts("| Total number of links                | #{link_lengths.length} |")
    puts("| ------------------------------------ | ------ |")
  else
    puts "No links were selected."
  end

rescue => e
  puts "[ERROR] #{e.message}"
  exit 1
ensure
  puts "[#{Time.now}] Script completed"
end
