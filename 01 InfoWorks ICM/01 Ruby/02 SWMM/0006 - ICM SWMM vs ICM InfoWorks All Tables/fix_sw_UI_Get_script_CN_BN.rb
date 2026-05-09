# frozen_string_literal: true
# ---------------------------------------------------------------------------
# fix_sw_UI_Get_script_CN_BN.rb
#
# Purpose : Iterate selected ICM SWMM links (sw_conduit), fetch time-series
#           result fields (FLOW, DEPTH, etc), compute integrated/sum/mean/
#           min/max/count, and print d/D and q/Q ratios using user_number_10
#           as full flow and conduit_height as diameter.
# Inputs  : Active ICM SWMM current_network with at least one selection and
#           simulation results loaded.
# Outputs : Console rows with statistics per selected link.
# Type    : UI script.
# Hardening:
#   * frozen_string_literal pragma
#   * Validates current_network not nil
#   * Validates timesteps loaded
#   * Skips selections without matching row, nil diameter / full_flow
#   * Per-field rescue prevents one bad field aborting whole link
#   * begin/rescue/ensure around main logic
#   * Timestamped logging
# ---------------------------------------------------------------------------

require 'date'

def log(msg)
  puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] #{msg}"
end

begin
  net = WSApplication.current_network
  raise 'No current network is open.' if net.nil?

  ts = net.list_timesteps
  raise 'No timesteps - load simulation results before running.' if ts.nil? || ts.empty?

  ts_size = ts.count

  field_names = %w[
    FLOW MAX_FLOW DEPTH VELOCITY MAX_VELOCITY HGL FLOW_VOLUME FLOW_CLASS
    CAPACITY MAX_CAPACITY SURCHARGED ENTRY_LOSS EXIT_LOSS
  ]

  net.each_selected do |sel|
    begin
      ro = net.row_object('_links', sel.id)
      next if ro.nil?

      diameter  = ro.conduit_height ? ro.conduit_height / 1000.0 : nil
      full_flow = ro.user_number_10

      if full_flow.nil? || diameter.nil?
        puts "Link: #{format('%-12s', sel.id)} has nil values for diameter or full flow."
      else
        puts "Link: #{format('%-12s', sel.id)} | Diameter: #{format('%12.3f', diameter)} | Full Flow: #{format('%11.3f', full_flow)}"
      end

      field_names.each do |res_field_name|
        begin
          field_data = ro.results(res_field_name)
          next if field_data.nil?
          rs_size = field_data.count
          next unless rs_size == ts_size

          total = 0.0
          total_integrated_over_time = 0.0
          min_value = Float::INFINITY
          max_value = -Float::INFINITY
          count = 0

          time_interval = ts.size > 1 ? (ts[1] - ts[0]) * 24 * 60 * 60 : 0

          field_data.each_with_index do |result, _step|
            v = result.to_f
            total += v
            if res_field_name == 'FLOW'
              total_integrated_over_time += v * time_interval
            else
              total_integrated_over_time = v
            end
            min_value = v if v < min_value
            max_value = v if v > max_value
            count += 1
          end

          mean_value = count.positive? ? total / count : 0

          puts "Link: #{format('%-12s', sel.id)} | Field: #{format('%-12s', res_field_name)} | Sum: #{format('%15.4f', total_integrated_over_time)} | Mean: #{format('%15.4f', mean_value)} | Max: #{format('%15.5f', max_value)} | Min: #{format('%15.5f', min_value)} | Steps: #{format('%15d', count)}"

          if res_field_name == 'DEPTH' && diameter && diameter > 0
            puts "Link: #{format('%-12s', sel.id)} | Field: d/D          | Sum: #{format('%15.4f', total_integrated_over_time / diameter)} | Mean: #{format('%15.4f', mean_value / diameter)} | Max: #{format('%15.5f', max_value / diameter)} | Min: #{format('%15.5f', min_value / diameter)} | Diameter: #{format('%12.3f', diameter)}"
          end
          if res_field_name == 'FLOW' && full_flow && full_flow != 0
            puts "Link: #{format('%-12s', sel.id)} | Field: q/Q          | Sum: #{format('%15.4f', total_integrated_over_time / full_flow)} | Mean: #{format('%15.4f', mean_value / full_flow)} | Max: #{format('%15.5f', max_value / full_flow)} | Min: #{format('%15.5f', min_value / full_flow)} | Full Flow: #{format('%11.3f', full_flow)}"
          end
        rescue StandardError
          next
        end
      end
    rescue StandardError => e
      puts "Error processing link with ID #{sel.id}. Error: #{e.message}"
    end
  end
rescue StandardError => e
  log "Aborted: #{e.message}"
ensure
  log 'fix_sw_UI_Get_script_CN_BN.rb finished.'
end
