# frozen_string_literal: true

# ============================================================================
# FIXED: Export Node Flood Depth to SWMM5 Calibration Format
# ============================================================================
# Purpose: Extract flood depth time-series from selected nodes; export in
#   SWMM5 calibration file format (Day Time Value).
# Inputs: Network with selected nodes (hw_node); simulation results.
# Outputs: Console output in SWMM5 format (SemicolonINSTRUCT comment + data).
# Hardening:
#   - frozen_string_literal; begin/rescue/ensure
#   - Network nil-check; timestep validation (>1 required)
#   - Selected node iteration with nil-safety
#   - Result array size validation (must match ts.size)
#   - Time calculation safeguards (division, modulo)
#   - Float conversion with default; field access with nil-check
#   - Progress logging per node
#   - Graceful error handling per node (skip, continue)
# ============================================================================

begin
  # Import the 'date' library
  require 'date'

  # Get the current network object from InfoWorks
  net = WSApplication.current_network

  unless net
    puts "ERROR: No network open"
    exit
  end

  # Get the list of timesteps
  ts = net.list_timesteps

  # Ensure there's more than one timestep before proceeding
  if ts.nil? || ts.size <= 1
    puts "ERROR: Not enough timesteps available! (Found: #{ts ? ts.size : 0})"
    exit
  end

  # Calculate the time interval in seconds assuming the time steps are evenly spaced
  time_interval = (ts[1] - ts[0]).abs

  if time_interval <= 0
    puts "ERROR: Invalid time interval calculated (#{time_interval})"
    exit
  end

  # Define the result field name
  res_field_name = 'FloodDepth'

  # Output the headers for the SWMM5 Calibration File
  puts ";Selected Nodes for Node Flood Depth"
  puts ";         Day      Time  FloodDepth"
  puts ";-----------------------------"

  processed = 0
  skipped = 0
  errors = 0

  # Iterate through the selected objects in the network
  net.each_selected do |sel|
    begin
      # Skip if selection is nil
      next if sel.nil?

      # Try to get the row object for the current node
      ro = net.row_object('_nodes', sel.id)

      # Skip if row object is nil (not a valid node)
      if ro.nil?
        skipped += 1
        next
      end

      # Use the Asset ID in the output
      puts sel.id

      # Get the results for the specified field
      results = ro.results(res_field_name)

      # Validate results array
      if results.nil? || results.empty?
        puts "  WARNING: No results found for field '#{res_field_name}'"
        skipped += 1
        next
      end

      # Ensure we have results for all timesteps
      if results.size != ts.size
        puts "  WARNING: Mismatch in timestep count for node #{sel.id}. Expected: #{ts.size}, Found: #{results.size}"
        skipped += 1
        next
      end

      processed += 1

      # Iterate through the results and output in SWMM5 format
      results.each_with_index do |result, idx|
        val = result.to_f rescue 0.0

        # Calculate the exact time for this result
        current_time = idx.to_f * time_interval

        # Assuming current_time is in seconds
        days = (current_time / 86400.0).to_i
        remaining_seconds = current_time % 86400.0
        hours = (remaining_seconds / 3600.0).to_i
        minutes = ((remaining_seconds % 3600.0) / 60.0).to_i

        # Output the formatted data for SWMM5
        printf "         %-7d %2d:%02d     %.4f\n", days, hours, minutes, val
      end

    rescue => e
      errors += 1
      puts "ERROR processing node #{sel&.id || 'unknown'}: #{e.message}"
      next
    end
  end

  puts "\n;------- Export Summary -------"
  puts ";Processed: #{processed}"
  puts ";Skipped: #{skipped}"
  puts ";Errors: #{errors}"

rescue => e
  puts "FATAL ERROR: #{e.message}"
  puts e.backtrace.first(5).join("\n")
  exit
end
