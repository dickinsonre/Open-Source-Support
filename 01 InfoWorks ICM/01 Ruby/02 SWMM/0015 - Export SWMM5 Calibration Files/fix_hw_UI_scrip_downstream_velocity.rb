# frozen_string_literal: true
# =============================================================================
# fix_hw_UI_scrip_downstream_velocity.rb
# =============================================================================
# Purpose:
#   Hardened SWMM5 calibration export for downstream velocity (ds_vel) on
#   selected conduits. Reads the per-link ds_vel time-series from the current
#   network and prints SWMM5-style Day/Time/Velocity rows.
#
# Inputs:
#   - Current network with results loaded
#   - User selection of conduits (_links)
#
# Outputs:
#   - Console SWMM5 calibration block (header + per-link Day/Time/Velocity)
#
# UI vs Exchange:
#   UI script.
#
# Hardening notes:
#   - frozen_string_literal, timestamped logging
#   - begin/rescue/ensure wrap; per-row rescue
#   - validates network, timesteps, per-row results
#   - safer asset_id retrieval (nil-safe via &.)
# =============================================================================

require 'date'

def ts_log(msg)
  warn "[#{Time.now.strftime('%H:%M:%S')}] #{msg}"
end

begin
  ts_log "Starting Downstream Velocity SWMM5 calibration export"

  cn = WSApplication.current_network
  raise "No current network." if cn.nil?

  ts = cn.list_timesteps
  raise "No timesteps available." if ts.nil? || ts.empty?
  if ts.size <= 1
    ts_log "Not enough timesteps available!"
    return
  end

  time_interval = (ts[1] - ts[0]).abs
  raise "Invalid time interval (#{time_interval})." if time_interval <= 0

  res_field_name = 'ds_vel'

  puts ";Flows for Selected Conduits for Downstream Velocity"
  puts ";Conduit  Day      Time  Velocity"
  puts ";-----------------------------"

  processed = skipped = errors = 0

  cn.each_selected do |sel|
    next if sel.nil?
    begin
      ro = cn.row_object('_links', sel.id)
      if ro.nil?
        skipped += 1
        next
      end
      asset_id = (ro.asset_id rescue nil) || sel.id
      puts asset_id
      results = ro.results(res_field_name) rescue nil
      if results.nil? || results.empty?
        skipped += 1
        next
      end
      if results.size != ts.size
        ts_log "Mismatch ts count for #{sel.id}"
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
  ts_log "Downstream Velocity export finished"
end
