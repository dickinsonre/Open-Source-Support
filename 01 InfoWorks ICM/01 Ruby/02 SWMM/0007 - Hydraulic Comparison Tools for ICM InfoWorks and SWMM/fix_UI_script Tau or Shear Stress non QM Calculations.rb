# frozen_string_literal: true

# Purpose: Calculate tau (shear stress) in US or SI units for conduits with timestep statistics
# Inputs: Selected conduits, prompt for unit system (USA/SI)
# Outputs: Console output with mean/max/min tau statistics for upstream and downstream
# Type: UI Script (WSApplication.prompt, MessageBox)
# Hardening: nil-safety, unit selection validation, empty results handling, zero-check on division

require 'date'

def print_table_results(cn)
  return if cn.nil?
  puts
  puts "Tables and their result fields in this ICM InfoWorks Run"
  puts
  cn.tables&.each do |table|
    results_array = []
    found_results = false

    cn.row_object_collection(table.name)&.each do |row_object|
      if row_object.table_info&.results_fields && !found_results
        row_object.table_info.results_fields.each do |field|
          results_array << field.name
        end
        found_results = true
        break
      end
    end

    unless results_array.empty?
      puts "Table: #{table.name.upcase}"
      results_array.each { |field| puts "Result field: #{field}" }
      puts
    end
  end
end

begin
  cn = WSApplication.current_network
  raise "Network is nil" if cn.nil?

  val = WSApplication.prompt(
    "Choose USA or SI Units for the Tau calculation",
    [
      ['USA Units', 'Boolean', false],
      ['SI  Units', 'Boolean', true]
    ],
    false
  )
  raise "User cancelled prompt" if val.nil?

  usa = val[0]
  si = val[1]
  raise "No unit system selected" if !usa && !si

  ts_size = cn.list_timesteps.count
  puts "[#{Time.now.strftime('%H:%M:%S')}] Starting tau calculation: ts_size=#{ts_size}, USA=#{usa}, SI=#{si}"

  ts = cn.list_timesteps
  raise "Insufficient timesteps" if ts.nil? || ts.size < 2

  time_interval = (ts[1] - ts[0]).abs
  puts "Time interval: #{(time_interval * 86400.0).round(4)} seconds or #{(time_interval * 1440.0).round(4)} minutes"

  selected_count = 0
  cn.each_selected do |sel|
    begin
      selected_count += 1
      ro = cn.row_object('hw_conduit', sel.id)
      next if ro.nil?

      us_tau_values = []
      ds_tau_values = []

      (0...ts_size).each do |time_step_index|
        density = usa ? 62.4 : 998.34

        us_depth_results = ro.results('us_depth')
        ds_depth_results = ro.results('ds_depth')
        hydgrad_results = ro.results('HYDGRAD')

        if us_depth_results.nil? || ds_depth_results.nil? || hydgrad_results.nil?
          puts "[#{Time.now.strftime('%H:%M:%S')}] Warning: Missing depth/gradient results for #{sel.id}"
          next
        end

        us_depth_val = us_depth_results[time_step_index].to_f rescue 0.0
        ds_depth_val = ds_depth_results[time_step_index].to_f rescue 0.0
        hydgrad_val = hydgrad_results[time_step_index].to_f rescue 0.0

        us_tau_calc = density * hydgrad_val.abs * us_depth_val
        ds_tau_calc = density * hydgrad_val.abs * ds_depth_val

        us_tau_values << us_tau_calc
        ds_tau_values << ds_tau_calc
      end

      if us_tau_values.empty? || ds_tau_values.empty?
        puts "[#{Time.now.strftime('%H:%M:%S')}] Warning: No valid tau values for #{sel.id}"
        next
      end

      us_tau_mean = us_tau_values.sum.to_f / us_tau_values.size
      us_tau_max = us_tau_values.max
      us_tau_min = us_tau_values.min

      ds_tau_mean = ds_tau_values.sum.to_f / ds_tau_values.size
      ds_tau_max = ds_tau_values.max
      ds_tau_min = ds_tau_values.min

      puts "ID: #{'%20s' % sel.id} | US Tau - Mean: #{'%11.4f' % us_tau_mean}, Max: #{'%11.4f' % us_tau_max}, Min: #{'%11.4f' % us_tau_min} | DS Tau - Mean: #{'%11.4f' % ds_tau_mean}, Max: #{'%11.4f' % ds_tau_max}, Min: #{'%11.4f' % ds_tau_min}"
    rescue => e
      puts "[#{Time.now.strftime('%H:%M:%S')}] Error processing link #{sel.id}: #{e.message}"
    end
  end

  puts "[#{Time.now.strftime('%H:%M:%S')}] Completed: processed #{selected_count} selected conduits"

rescue => e
  puts "[#{Time.now.strftime('%H:%M:%S')}] Fatal error: #{e.message}"
  puts e.backtrace.first(5)
ensure
  puts "[#{Time.now.strftime('%H:%M:%S')}] Script ended"
end
