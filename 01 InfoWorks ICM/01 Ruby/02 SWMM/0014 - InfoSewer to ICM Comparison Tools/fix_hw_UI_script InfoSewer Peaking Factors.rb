# frozen_string_literal: true
# =============================================================================
# fix_hw_UI_script InfoSewer Peaking Factors.rb
# =============================================================================
# Purpose:
#   Hardened InfoSewer-style peaking factor calculator for ICM InfoWorks.
#   Computes per-link peaking factors using k * Q^p (or alternative curve)
#   and writes results back to base_flow / trade_flow / additional_foul_flow
#   / conduit_flow on selected links.
#
# Inputs:
#   - Current network in EDIT mode (read-only mode is detected and reported)
#   - Selection of links
#   - User parameters via WSApplication.prompt
#
# Outputs:
#   - Console phase logs and summary table
#   - Field updates on selected links (when network is editable)
#
# UI vs Exchange:
#   UI script - uses current_network, prompt, message_box.
#
# Hardening notes:
#   - frozen_string_literal + timestamped progress logging
#   - Begin/rescue/ensure wrap around the whole calculator
#   - Validates prompt cancellation, timesteps, parameters, selection
#   - Phase 2 skipped automatically if read-only detected
#   - Per-link try/rescue so a single failure doesn't kill the run
# =============================================================================

require 'date'

def ts_log(msg)
  puts "[#{Time.now.strftime('%H:%M:%S')}] #{msg}"
end

begin
  puts "\n" + "=" * 80
  puts "ICM InfoWorks Peaking Factor Calculator (hardened)"
  puts "Script Start: #{DateTime.now}"
  puts "=" * 80

  cn = WSApplication.current_network
  raise "No current network." if cn.nil?

  ts_log "Checking network access mode..."

  network_read_only = false
  begin
    test_node = cn.row_objects('Node').first rescue nil
    if test_node
      current_val = test_node['user_text_10'] rescue ''
      begin
        test_node['user_text_10'] = current_val
        test_node.write
        ts_log "Network is WRITABLE (edit mode)"
      rescue => e
        if e.message.to_s.include?('read only')
          network_read_only = true
          ts_log "WARNING: Network is READ-ONLY!"
        end
      end
    end
  rescue => e
    ts_log "Could not determine network mode: #{e.message}"
  end

  if network_read_only
    ans = WSApplication.prompt(
      "Network is read-only. Cannot write to fields.\n\nDo you want to continue anyway?\n(Will only calculate, not save results)",
      [['Continue in read-only mode (no data saved)', 'Boolean', false]],
      false
    )
    unless ans && ans[0]
      ts_log "Script cancelled. Open network in edit mode and try again."
      return
    end
    ts_log "Continuing in read-only mode (no data saved)."
  end

  parameters = WSApplication.prompt "Making ICM InfoWorks Approximate InfoSewer Peaking Factors\n" \
    "Note: Unpeakable flow should be in base_flow, peakable load in trade_flow, and coverage in additional_foul_flow.",
  [
    ['Use USA Units (GPM)', 'Boolean', false],
    ['Use SI Units (L/s)', 'Boolean', true],
    ['Save Peak Flow (Calc) to Inflow Conduit Field', 'Boolean', true],
    ['Include Peak Flow Calculation', 'Boolean', true],
    ['Unpeakable Flow as Base Flow', 'Boolean', true],
    ['Peakable Point Flow as Trade Flow', 'Boolean', true],
    ['Peakable Coverage as Additional Foul Flow', 'Boolean', true],
    ['Enter value for k (Peaking Factor)', 'String', '1.0'],
    ['Enter value for p (Exponent)', 'String', '2.0'],
    ['Use Peakable Coverage Load', 'Boolean', true],
    ['Enter value for peakable coverage load', 'String', '0.0'],
    ['Enter value for a', 'String', '0.0'],
    ['Enter value for b', 'String', '0.0'],
    ['Enter value for c', 'String', '0.0'],
    ['Enter value for d', 'String', '0.0'],
    ['Enter value for e', 'String', '0.0'],
    ['Alternative Peaking Curve', 'Boolean', false],
    ['X Coverage', 'NUMBER', 23, nil, 'LIST', [0,1,5,10,50]],
    ['Y Peaking Multiplier', 'NUMBER', 23, nil, 'LIST', [0,2,15,20,90]]
  ], false

  if parameters.nil?
    ts_log "User cancelled."
    return
  end

  use_usa_units = parameters[0]
  use_si_units = parameters[1]
  save_peak_flow = parameters[2]
  include_peak_flow = parameters[3]
  unpeakable_flow_as_base_flow = parameters[4]
  peakable_point_flow_as_trade_flow = parameters[5]
  peakable_coverage_as_additional_foul_flow = parameters[6]
  k_value = parameters[7].to_f
  p_value = parameters[8].to_f
  use_peakable_coverage_load = parameters[9]
  peakable_coverage_load = parameters[10].to_f
  a_value = parameters[11].to_f
  b_value = parameters[12].to_f
  c_value = parameters[13].to_f
  d_value = parameters[14].to_f
  e_value = parameters[15].to_f
  alternative_peaking_curve = parameters[16]
  x_coverage = parameters[17].to_f
  y_peaking_multiplier = parameters[18].to_f

  ts_log "Parameters: k=#{k_value}, p=#{p_value}, peakable_coverage_load=#{peakable_coverage_load}, alt=#{alternative_peaking_curve}"

  ts = cn.list_timesteps
  raise "No timesteps available - load results first." if ts.nil? || ts.empty?
  if ts.size <= 1
    ts_log "ERROR: Not enough timesteps available! (Found: #{ts.size})"
    return
  end
  ts_log "Timesteps: #{ts.size}"

  res_field_name = 'us_flow'

  puts "\n" + "=" * 80
  puts "PHASE 1: Calculating statistics for each link"
  puts "=" * 80
  link_data = {}

  cn.each_selected do |sel|
    next if sel.nil?
    begin
      ro = cn.row_object('_links', sel.id)
      if ro.nil?
        ts_log "WARNING: Could not get link object for #{sel.id}"
        next
      end

      results = ro.results(res_field_name) rescue nil
      next if results.nil?

      if results.size == ts.size
        total_flow = 0.0
        count = 0
        min_value = results.first.to_f
        max_value = results.first.to_f
        peak_flow_sum = 0.0

        results.each do |result|
          flow_value = result.to_f
          if alternative_peaking_curve && a_value != 0.0 && b_value != 0.0
            if flow_value > 0
              denom = (flow_value * b_value) ** p_value
              peak_factor = denom != 0.0 ? a_value / denom : k_value
            else
              peak_factor = k_value
            end
            peak_flow = flow_value * peak_factor
          else
            peak_flow = k_value * (flow_value ** p_value)
          end

          total_flow += flow_value
          peak_flow_sum += peak_flow
          min_value = [min_value, flow_value].min
          max_value = [max_value, flow_value].max
          count += 1
        end

        mean_value = count > 0 ? total_flow / count : 0.0
        mean_peak  = count > 0 ? peak_flow_sum / count : 0.0
        link_data[sel.id] = {
          total_flow: total_flow, mean_flow: mean_value, min_flow: min_value,
          max_flow: max_value, mean_peak: mean_peak, count: count
        }
        puts format("Link: %-12s | Mean: %10.4f | Max: %10.4f | Min: %10.4f | Peak: %10.4f | Steps: %5d",
                    sel.id, mean_value, max_value, min_value, mean_peak, count)
      else
        ts_log "Mismatch in timestep count for link #{sel.id}: expected #{ts.size}, got #{results.size}"
      end
    rescue => e
      ts_log "ERROR processing link #{sel.id rescue '?'}: #{e.message}"
    end
  end
  ts_log "Phase 1 complete. Stored data for #{link_data.size} links"

  puts "\n" + "=" * 80
  puts "PHASE 2: Assigning values to link fields"
  puts "=" * 80
  if network_read_only
    ts_log "SKIPPING Phase 2 - Network is read-only. Calculations not saved."
  else
    assigned_count = 0
    error_count = 0
    cn.each_selected do |sel|
      next if sel.nil?
      begin
        ro = cn.row_object('_links', sel.id)
        if ro.nil?
          ts_log "WARNING: Could not get link object for #{sel.id}"
          next
        end
        data = link_data[sel.id]
        if data.nil?
          ts_log "WARNING: No calculated data found for link #{sel.id}"
          next
        end
        total_flow = data[:total_flow]
        if unpeakable_flow_as_base_flow
          ro['base_flow'] = total_flow - peakable_coverage_load
        end
        if peakable_point_flow_as_trade_flow
          ro['trade_flow'] = peakable_coverage_load
        end
        if peakable_coverage_as_additional_foul_flow
          ro['additional_foul_flow'] = x_coverage * y_peaking_multiplier
        end
        if save_peak_flow
          begin
            ro['conduit_flow'] = data[:mean_peak]
          rescue => e
            ts_log "Could not write conduit_flow on #{sel.id}: #{e.message}"
          end
        end
        ro.write
        assigned_count += 1
      rescue => e
        error_count += 1
        if e.message.to_s.include?('read only')
          ts_log "ERROR: Network became read-only during execution. Stopping Phase 2."
          break
        else
          ts_log "ERROR assigning values to link #{sel.id rescue '?'}: #{e.message}"
        end
      end
    end
    ts_log "Phase 2 complete: #{assigned_count} written, #{error_count} errors"
  end

  puts "\n" + "=" * 80
  puts "SCRIPT COMPLETE  #{DateTime.now}"
  puts "=" * 80

rescue => e
  ts_log "FATAL: #{e.class}: #{e.message}"
  puts e.backtrace.first(5).join("\n") if e.backtrace
ensure
  ts_log "Peaking Factors run finished"
end
