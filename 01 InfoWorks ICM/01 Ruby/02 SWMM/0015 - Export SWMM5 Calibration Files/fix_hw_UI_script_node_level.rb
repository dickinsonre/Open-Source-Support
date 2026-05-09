# frozen_string_literal: true
# =============================================================================
# fix_hw_UI_script_node_level.rb
# =============================================================================
# Purpose:
#   Hardened SWMM5 calibration export for node depth (DEPNOD) on selected
#   nodes. Output uses Day/Time/DEPNOD format.
#
# Inputs:
#   - Current network with results
#   - Selected nodes (_nodes)
#
# Outputs:
#   - Console SWMM5 calibration block
#
# UI vs Exchange: UI script.
#
# Hardening notes:
#   - frozen_string_literal, begin/rescue/ensure, timestamped logging
#   - per-row rescue; validates ts/results.size
# =============================================================================

require 'date'

def ts_log(msg)
  warn "[#{Time.now.strftime('%H:%M:%S')}] #{msg}"
end

begin
  ts_log "Starting Node Level SWMM5 calibration export"

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

  res_field_name = 'DEPNOD'

  puts ";Selected Nodes for Node Level"
  puts ";         Day      Time  DEPNOD"
  puts ";-----------------------------"

  processed = skipped = errors = 0

  net.each_selected do |sel|
    next if sel.nil?
    begin
      ro = net.row_object('_nodes', sel.id)
      if ro.nil?
        skipped += 1
        next
      end
      puts sel.id
      results = ro.results(res_field_name) rescue nil
      if results.nil? || results.empty? || results.size != ts.size
        skipped += 1
        next
      end
      processed += 1
      results.each_with_index do |r, idx|
        val = r.to_f rescue 0.0
        current_time = idx.to_f * time_interval
        days = (current_time / 86400.0).to_i
        rem = current_time % 86400.0
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
  ts_log "Node Level export finished"
end
