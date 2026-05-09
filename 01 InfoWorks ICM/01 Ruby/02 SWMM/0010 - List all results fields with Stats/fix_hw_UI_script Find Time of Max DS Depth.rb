# frozen_string_literal: true

# Find Time of Max DS Depth
#
# Purpose: Locate and report maximum downstream depth and timestamp for selected links
# Inputs: Network (net), Selected link objects, Simulation results (.iwr file)
# Outputs: Console output with formatted results per link
# UI/EX: InfoWorks ICM UI script execution
#
# Hardening:
# - Added frozen_string_literal for performance
# - Wrapped in begin/rescue/ensure for error handling
# - Validates network, timesteps, and results availability
# - Checks results count matches timesteps before processing
# - Safe type conversion with error handling
# - Nil-safety with respond_to? guards

begin
  require 'date'

  net = WSApplication.current_network
  raise "No network loaded" if net.nil?

  ts = net.list_timesteps
  raise "No timesteps available" if ts.nil? || ts.empty?

  # Calculate time interval
  if ts.size > 1
    time_interval = (ts[1] - ts[0]).abs
  else
    puts "Warning: Only one timestep available"
    time_interval = 0
  end

  res_field_name = 'ds_depth'
  links_processed = 0

  net.each_selected do |sel|
    begin
      # Validate object is a link
      ro = net.row_object('_links', sel.id)
      next if ro.nil?

      # Get results with validation
      results = ro.respond_to?(:results) ? ro.results(res_field_name) : nil
      next unless results && results.size == ts.size

      # Find maximum value and index
      max_value = results.first.to_f
      max_index = 0

      results.each_with_index do |result, index|
        val = result.to_f
        if val.finite? && val > max_value
          max_value = val
          max_index = index
        end
      end

      # Calculate time of maximum
      total_seconds = max_index * time_interval
      days = total_seconds.to_i / (24 * 3600)
      remaining_seconds = total_seconds.to_i % (24 * 3600)
      hours = remaining_seconds / 3600
      remaining_seconds %= 3600
      minutes = remaining_seconds / 60
      seconds = remaining_seconds % 60

      formatted_time = "#{days}d #{hours}h #{minutes}m #{seconds}s"

      puts "Link ID: #{sel.id} | Max DS Depth: #{'%9.3f' % max_value} at Time: #{formatted_time}"
      links_processed += 1

    rescue StandardError => e
      puts "Warning: Error processing link #{sel.id}: #{e.message}"
    end
  end

  puts "Processed #{links_processed} links successfully"

rescue StandardError => e
  puts "Fatal error: #{e.message}"
  puts e.backtrace.join("\n")

ensure
  puts "Script finished at #{Time.now}"
end
