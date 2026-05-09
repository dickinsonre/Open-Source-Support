# frozen_string_literal: true
# =============================================================================
# fix_hw_UI_script  InfoSewer Gravity Main Report, from ICM InfoWorks.rb
# =============================================================================
# Purpose:
#   Hardened version of the InfoSewer Gravity Main Report script. Iterates the
#   selected hw_conduit links in the current InfoWorks network, reads simulated
#   us_depth/us_flow/ds_depth/ds_flow over all timesteps, computes ratios
#   (d/D and Q/Qfull), prints stats, and selects the top 10 links by us_d/D
#   and ds_d/D.
#
# Inputs:
#   - Current network (must be open and have results loaded)
#   - User selection (one or more hw_conduit links)
#
# Outputs:
#   - Console statistics per selected link
#   - Selection updated to top 10 links by us_d/D and ds_d/D
#
# UI vs Exchange:
#   UI script - uses WSApplication.current_network and net.clear_selection.
#
# Hardening notes:
#   - Validates network, timesteps, selection, row objects
#   - Guards divisions (capacity, conduit_height) against zero/nil
#   - Wraps top-level logic in begin/rescue/ensure with timestamped logging
#   - Skips malformed result rows instead of aborting
# =============================================================================

require 'date'

def ts_log(msg)
  puts "[#{Time.now.strftime('%H:%M:%S')}] #{msg}"
end

begin
  ts_log "Starting Gravity Main Report"

  net = WSApplication.current_network
  raise "No current network - open a network with results before running." if net.nil?

  top_values = {}
  max_values = {}

  ts = net.list_timesteps
  raise "No timesteps available - run/load a simulation first." if ts.nil? || ts.empty?
  if ts.size <= 1
    ts_log "Not enough timesteps available! (#{ts.size})"
    next_action = nil
    return
  end

  time_interval = (ts[1] - ts[0]).abs
  ts_log format("Time interval: %.4f seconds or %.4f minutes", time_interval, time_interval / 60.0)

  res_field_names = ['us_depth', 'us_flow', 'ds_depth', 'ds_flow']

  selected_count = 0
  net.each_selected do |sel|
    selected_count += 1
    next if sel.nil?
    begin
      ro = net.row_object('_links', sel.id)
      next if ro.nil?

      capacity = ro.capacity rescue nil
      conduit_height = ro.conduit_height rescue nil

      us_d_over_D_values = []
      us_q_over_Qfull_values = []
      ds_d_over_D_values = []
      ds_q_over_Qfull_values = []

      res_field_names.each do |res_field_name|
        results = ro.results(res_field_name) rescue nil
        next if results.nil?

        if results.size == ts.size
          total = 0.0
          count = 0
          min_value = results.first.to_f
          max_value = results.first.to_f

          results.each do |result|
            val = result.to_f
            total += val
            min_value = [min_value, val].min
            max_value = [max_value, val].max
            count += 1

            case res_field_name
            when 'us_depth'
              if conduit_height && conduit_height.to_f > 0
                us_d_over_D_values << val / (conduit_height.to_f / 100.0)
              end
            when 'us_flow'
              us_q_over_Qfull_values << val / capacity.to_f if capacity && capacity.to_f != 0.0
            when 'ds_depth'
              if conduit_height && conduit_height.to_f > 0
                ds_d_over_D_values << val / (conduit_height.to_f / 100.0)
              end
            when 'ds_flow'
              ds_q_over_Qfull_values << val / capacity.to_f if capacity && capacity.to_f != 0.0
            end
          end

          mean_value = count > 0 ? total / count : 0.0
          puts "Link: #{'%-12s' % sel.id} | Field: #{'%-19s' % res_field_name} | Mean: #{'%15.5f' % mean_value} | Max: #{'%15.5f' % max_value} | Min: #{'%15.5f' % min_value} | Steps: #{'%10d' % count}"
        else
          ts_log "Mismatch in timestep count for object ID #{sel.id}. Expected: #{ts.size}, Found: #{results.size}"
        end
      end

      [
        ['us_d_over_D',     us_d_over_D_values],
        ['us_q_over_Qfull', us_q_over_Qfull_values],
        ['ds_d_over_D',     ds_d_over_D_values],
        ['ds_q_over_Qfull', ds_q_over_Qfull_values]
      ].each do |label, vals|
        next if vals.empty?
        mean = vals.sum / vals.size
        min, max = vals.minmax
        puts "Link: #{'%-12s' % sel.id} | Field: #{'%-19s' % label} | Mean: #{'%15.5f' % mean} | Max: #{'%15.5f' % max} | Min: #{'%15.5f' % min} | Steps: #{'%10d' % vals.size} | Capacity: #{'%15.5f' % (capacity || 0.0)} | Conduit Height: #{'%15.5f' % (conduit_height || 0.0)}"
      end

      max_values[sel.id] ||= {}
      max_values[sel.id]['us_d_over_D'] = us_d_over_D_values.max if us_d_over_D_values.any?
      max_values[sel.id]['ds_d_over_D'] = ds_d_over_D_values.max if ds_d_over_D_values.any?

    rescue => e
      ts_log "Error processing link #{sel.id rescue '?'}: #{e.message}"
    end
  end

  ts_log "Selected objects iterated: #{selected_count}"
  net.clear_selection

  top_links_us = max_values.select { |_, f| f && f['us_d_over_D'] }
                           .sort_by { |_, f| -f['us_d_over_D'] }.first(10).map(&:first)
  top_links_ds = max_values.select { |_, f| f && f['ds_d_over_D'] }
                           .sort_by { |_, f| -f['ds_d_over_D'] }.first(10).map(&:first)

  net.row_objects('hw_conduit').each do |ro|
    next if ro.nil?
    if top_links_us.include?(ro.id) || top_links_ds.include?(ro.id)
      ro.selected = true
    end
  end

  ts_log "Top 10 links for us_d_over_D: #{top_links_us.join(', ')}"
  ts_log "Top 10 links for ds_d_over_D: #{top_links_ds.join(', ')}"

rescue => e
  ts_log "FATAL: #{e.class}: #{e.message}"
  puts e.backtrace.first(5).join("\n") if e.backtrace
ensure
  ts_log "Gravity Main Report finished"
end
