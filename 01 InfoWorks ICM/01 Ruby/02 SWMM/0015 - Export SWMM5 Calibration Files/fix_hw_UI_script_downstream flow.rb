# frozen_string_literal: true
# =============================================================================
# fix_hw_UI_script_downstream flow.rb
# =============================================================================
# Purpose:
#   Hardened SWMM5 calibration export for downstream flow (ds_flow) on
#   selected conduits. The original used a hard-coded asset_mapping hash to
#   translate InfoWorks IDs to SWMM5 IDs; this hardened version preserves
#   that mapping and falls back to the InfoWorks ID when no mapping is found.
#
# Inputs:
#   - Current network with results loaded
#   - User selection of conduit links
#   - Edit asset_mapping at top of file to suit your network
#
# Outputs:
#   - Console SWMM5 calibration block
#
# UI vs Exchange: UI script.
#
# Hardening notes:
#   - frozen_string_literal, timestamped logging, begin/rescue/ensure
#   - validates network, timesteps; per-row rescue
#   - asset_id falls back to sel.id if not in mapping
# =============================================================================

require 'date'

def ts_log(msg)
  warn "[#{Time.now.strftime('%H:%M:%S')}] #{msg}"
end

begin
  ts_log "Starting Downstream Flow SWMM5 calibration export"

  net = WSApplication.current_network
  raise "No current network." if net.nil?

  asset_mapping = {
    'mid9.1' => 'outlet',
    'Inflow.1' => 'pipe1',
    'mid1.1' => 'pipe2',
    'mid2_1' => 'pipe3',
    'mid3.1' => 'pipe4',
    'mid4.1' => 'pipe5',
    'mid5.1' => 'pipe6',
    'mid6.1' => 'pipe7',
    'mid7.1' => 'pipe8',
    'mid8.1' => 'pipe9'
  }

  ts = net.list_timesteps
  raise "No timesteps available." if ts.nil? || ts.empty?
  if ts.size <= 1
    ts_log "Not enough timesteps available!"
    return
  end

  time_interval = (ts[1] - ts[0]).abs
  raise "Invalid time interval (#{time_interval})." if time_interval <= 0

  res_field_name = 'ds_flow'

  puts ";Flows for Selected Conduits for Downstream Flow"
  puts ";Conduit  Day      Time  Flow"
  puts ";-----------------------------"

  processed = skipped = errors = 0

  net.each_selected do |sel|
    next if sel.nil?
    begin
      ro = net.row_object('_links', sel.id)
      if ro.nil?
        skipped += 1
        next
      end
      asset_id = asset_mapping[sel.id] || sel.id
      puts asset_id
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
  ts_log "Downstream Flow export finished"
end
