# frozen_string_literal: true

# Purpose: HEC-22 inlet efficiency comparison for InfoWorks ICM nodes
# Inputs: Selected nodes with result data (DEPNOD, FloodDepth, GLLYFLOW, GTTRSPRD, INLETEFF, OVDEPNOD)
# Outputs: Console output with tabular comparison of ICM vs HEC-22 inlet calculations
# Type: UI Script (WSApplication, MessageBox, network/selection helpers)
# Hardening: nil-safety, zero-guard on division, empty results handling, timestep validation

require 'date'

NodeResultsDataFields = [
  'DEPNOD',
  'FloodDepth',
  'GLLYFLOW',
  'GTTRSPRD',
  'INLETEFF',
  'OVDEPNOD'
].freeze

begin
  net = WSApplication.current_network
  raise "Network is nil" if net.nil?

  ts = net.list_timesteps
  raise "No timesteps available" if ts.nil? || ts.empty?
  raise "Insufficient timesteps (need >= 2)" if ts.size <= 1

  time_interval = (ts[1] - ts[0]).abs

  header_fields = NodeResultsDataFields.map { |field| field.ljust(9) }.join(' ')
  puts "[#{Time.now.strftime('%H:%M:%S')}] Starting HEC-22 inlet efficiency comparison"
  puts ";#{'Node_ID'.ljust(11)} #{'Time'.ljust(8)} #{header_fields} inlet_eff_value hec22_spread hec22_eff hec22_eff_diff ICM_NEW_T ICM_OLD_T"

  selected_count = 0
  net.each_selected do |sel|
    begin
      selected_count += 1
      ro = net.row_object('_nodes', sel.id)
      next if ro.nil?

      count = 0
      ts.each_with_index do |_timestep, index|
        all_field_results = NodeResultsDataFields.map do |field|
          field_results = ro.results(field)
          if field_results.nil? || field_results.empty?
            puts "[#{Time.now.strftime('%H:%M:%S')}] Warning: Field '#{field}' not found for node #{sel.id}"
            'N/A'
          elsif field_results.size == ts.size
            val = field_results[index].to_f
            format('%.4f', val)
          else
            'N/A'
          end
        end

        current_time = count * time_interval
        depnod_idx = NodeResultsDataFields.index('DEPNOD')
        inleteff_idx = NodeResultsDataFields.index('INLETEFF')
        gllyflow_idx = NodeResultsDataFields.index('GLLYFLOW')
        gttrsprd_idx = NodeResultsDataFields.index('GTTRSPRD')

        depnod_value = all_field_results[depnod_idx].to_f rescue 0.0
        inlet_eff_value = all_field_results[inleteff_idx].to_f rescue 0.0
        inlet_flow_value = all_field_results[gllyflow_idx].to_f rescue 0.0

        hec22_spread = 0.87 * (inlet_flow_value**0.42) * 0.0003802**0.3 * (1.0 / (0.013 * 0.02)**0.6)
        icm_spread = all_field_results[gttrsprd_idx].to_f rescue 0.0

        icm_spreadsheet = 0
        icm_spread_old = 0

        if depnod_value >= 0.0
          if depnod_value > 0.0
            icm_spreadsheet = 1.469 * ((inlet_flow_value**1.02) / (depnod_value**1.6))
            icm_spread_old = 1.469 * ((inlet_flow_value**1.02) / (depnod_value**1.6)) * 0.2**0.6
          end
        end

        if ro.opening_length && ro.opening_length > 0 && hec22_spread > ro.opening_length
          hec22_eff = 1.0 - (1.0 - (ro.opening_length / hec22_spread)**1.8)
        else
          hec22_eff = 1.0
          inlet_eff_value = 1.0
        end

        hec22_eff_diff = hec22_eff - inlet_eff_value

        days = current_time / (24 * 60 * 60)
        remaining_seconds = current_time % (24 * 60 * 60)
        hours = remaining_seconds / (60 * 60)
        remaining_seconds %= (60 * 60)
        minutes = remaining_seconds / 60
        seconds = remaining_seconds % 60

        puts "#{sel.id.ljust(10)} #{format('%02d', hours)}:#{format('%02d', minutes)}:#{format('%02d', seconds)} " \
             "#{all_field_results.map { |result| result.ljust(10) }.join(' ')} #{'%10.4f' % inlet_eff_value} #{'%10.4f' % hec22_spread} #{'%10.4f' % hec22_eff} #{'%10.4f' % hec22_eff_diff} #{'%10.4f' % icm_spread_old} #{'%10.4f' % icm_spreadsheet}"
        count += 1
      end
    rescue => e
      puts "[#{Time.now.strftime('%H:%M:%S')}] Error processing node #{sel.id}: #{e.message}"
    end
  end

  puts "[#{Time.now.strftime('%H:%M:%S')}] Completed: processed #{selected_count} selected nodes"

rescue => e
  puts "[#{Time.now.strftime('%H:%M:%S')}] Fatal error: #{e.message}"
  puts e.backtrace.first(5)
ensure
  puts "[#{Time.now.strftime('%H:%M:%S')}] Script execution ended"
end
