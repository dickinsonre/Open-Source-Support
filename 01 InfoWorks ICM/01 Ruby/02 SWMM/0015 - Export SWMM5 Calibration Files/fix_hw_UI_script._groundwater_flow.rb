# frozen_string_literal: true
# =============================================================================
# fix_hw_UI_script._groundwater_flow.rb
# =============================================================================
# Purpose:
#   Hardened SWMM5 calibration export for subcatchment groundwater flow.
#   Iterates the selected hw_subcatchment objects in the current network,
#   reads the RUNOFF result series (used here as the per-subcatchment flow
#   series labelled "Groundwater Flow" in the original script), and prints
#   them in SWMM5 calibration format (Day Time Value).
#
# Inputs:
#   - Current network (with results loaded)
#   - User selection of hw_subcatchment rows
#
# Outputs:
#   - Console SWMM5 calibration block (semicolon header + Day/Time/Value rows)
#
# UI vs Exchange:
#   UI script - uses WSApplication.current_network.
#
# Hardening notes:
#   - frozen_string_literal + timestamped progress logging
#   - begin/rescue/ensure top-level wrapper
#   - validates network, timesteps (>1), per-row results size
#   - per-row rescue so a single failure doesn't abort the export
#   - nil-safe reading of results
# =============================================================================

require 'date'

def ts_log(msg)
  warn "[#{Time.now.strftime('%H:%M:%S')}] #{msg}"
end

begin
  ts_log "Starting Groundwater Flow SWMM5 calibration export"

  net = WSApplication.current_network
  raise "No current network." if net.nil?

  ts = net.list_timesteps
  raise "No timesteps available." if ts.nil? || ts.empty?
  if ts.size <= 1
    ts_log "Not enough timesteps available!"
    return
  end

  time_interval = (ts[1] - ts[0]).abs
  raise "Invalid time interval (#{time_interval})." if time_interval <= 0

  res_field_name = 'RUNOFF'

  puts ";Selected Subcatchments for Groundwater Flow"
  puts ";         Day      Time  GroundwaterFlow"
  puts ";-----------------------------"

  processed = skipped = errors = 0

  net.each_selected do |sel|
    next if sel.nil?
    begin
      ro = net.row_object('hw_subcatchment', sel.id)
      if ro.nil?
        skipped += 1
        next
      end
      puts sel.id
      results = ro.results(res_field_name) rescue nil
      if results.nil? || results.empty?
        ts_log "WARNING: no '#{res_field_name}' results for #{sel.id}"
        skipped += 1
        next
      end
      if results.size != ts.size
        ts_log "Mismatch ts count for #{sel.id} (expected #{ts.size}, got #{results.size})"
        skipped += 1
        next
      end
      processed += 1
      results.each_with_index do |r, idx|
        val = r.to_f rescue 0.0
        current_time = idx.to_f * time_interval
        days = (current_time / 86400.0).to_i
        rem  = current_time % 86400.0
        hours = (rem / 3600.0).to_i
        minutes = ((rem % 3600.0) / 60.0).to_i
        printf "         %-7d %2d:%02d     %.4f\n", days, hours, minutes, val
      end
    rescue => e
      errors += 1
      ts_log "ERROR processing #{sel&.id}: #{e.message}"
    end
  end

  puts "\n;------- Export Summary -------"
  puts ";Processed: #{processed}"
  puts ";Skipped:   #{skipped}"
  puts ";Errors:    #{errors}"

rescue => e
  ts_log "FATAL: #{e.class}: #{e.message}"
  puts e.backtrace.first(5).join("\n") if e.backtrace
ensure
  ts_log "Groundwater Flow export finished"
end
