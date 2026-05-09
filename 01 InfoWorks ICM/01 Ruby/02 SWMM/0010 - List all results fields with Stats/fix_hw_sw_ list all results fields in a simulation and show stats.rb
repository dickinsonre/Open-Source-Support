# frozen_string_literal: true

# Combined Results Field Exporter with Automatic Field Detection and Statistics
#
# Purpose: Automatically detects result fields from simulation, exports user-selected
#          result data to CSV files, and calculates statistics (min, max, mean, std dev).
#
# Inputs: Network (cn via WSApplication.current_network), Simulation results (.iwr)
# Outputs: CSV files with summary and time-series data, console statistics
# UI/EX: InfoWorks ICM UI prompts for field & export options selection
#
# Hardening:
# - Added frozen_string_literal for performance
# - Wrapped in begin/rescue/ensure for error handling
# - Validates network, timesteps, and result fields before processing
# - Uses File.open/CSV.open block form for resource cleanup
# - Progress logging every 50 objects
# - Nil-safety with respond_to? checks and safe_format helper
# - Guards against missing fields with rescue NoMethodError

require 'csv'
require 'fileutils'
require 'date'

# --- Helper Functions for Statistics ---
def calculate_mean(arr)
  return nil if arr.nil? || arr.empty?
  arr.sum.to_f / arr.length
end

def calculate_std_dev(arr, mean)
  return nil if arr.nil? || arr.empty? || mean.nil? || arr.length < 2
  sum_sq_diff = arr.map { |x| (x - mean)**2 }.sum
  Math.sqrt(sum_sq_diff / (arr.length.to_f - 1.0))
end

# --- Safe numeric formatting ---
def safe_format(value, decimals = 4)
  return "0.0000" if value.nil?
  return "0.0000" unless value.respond_to?(:to_f)

  float_val = value.to_f
  return "0.0000" unless float_val.finite?

  begin
    sprintf("%.#{decimals}f", float_val)
  rescue StandardError
    "0.0000"
  end
end

# --- Get Result Fields from Network ---
def get_result_fields_from_network(cn)
  tables_with_results = {}

  puts "\nScanning network for result fields..."

  cn.tables.each do |table|
    results_array = []
    found_results = false

    begin
      cn.row_object_collection(table.name).each do |row_object|
        if row_object.respond_to?(:table_info) &&
           row_object.table_info.respond_to?(:results_fields) &&
           row_object.table_info.results_fields &&
           !found_results

          row_object.table_info.results_fields.each do |field|
            results_array << field.name
          end
          found_results = true
          break
        end
      end
    rescue StandardError => e
      puts "  Warning: Could not check table '#{table.name}': #{e.message}"
    end

    unless results_array.empty?
      tables_with_results[table.name] = results_array
      puts "  - #{table.name}: found #{results_array.length} result fields"
    end
  end

  puts "No result fields found in any tables." if tables_with_results.empty?

  tables_with_results
end

# --- UI-based field selection ---
def get_user_field_selection_ui(table_name, available_fields)
  field_prompts = [["Select ALL FIELDS", 'Boolean', false]]

  available_fields.each do |field|
    field_prompts << [field, 'Boolean', false]
  end

  user_selections = WSApplication.prompt(
    "Select #{table_name} Result Fields to Export",
    field_prompts,
    false
  )

  return [] if user_selections.nil?

  selected_fields = []
  select_all = user_selections[0]

  available_fields.each_with_index do |field, index|
    if select_all || user_selections[index + 1]
      selected_fields << field
    end
  end

  selected_fields
end

# --- Get export options via UI ---
def get_export_options_ui(table_name)
  desktop_path = File.join(ENV['HOME'] || ENV['USERPROFILE'], 'Desktop')

  options_prompts = [
    ['Export Folder', 'String', desktop_path, nil, 'FOLDER', 'Select Export Folder'],
    ['Calculate Statistics', 'Boolean', true],
    ['Export Time Series Data', 'Boolean', true],
    ['Export Summary Statistics', 'Boolean', true]
  ]

  user_options = WSApplication.prompt(
    "Export Options for #{table_name}",
    options_prompts,
    false
  )

  return nil if user_options.nil?

  {
    folder: user_options[0],
    calculate_stats: user_options[1],
    export_time_series: user_options[2],
    export_summary: user_options[3]
  }
end

# --- Process Single Table Results Export ---
def process_single_table_results(cn, selected_table_name, available_result_fields, timesteps, time_interval)
  puts "\n#{'='*20} Processing Table: #{selected_table_name.upcase} #{'='*20}"
  start_time = Time.now

  result_fields = available_result_fields[selected_table_name]
  if result_fields.nil? || result_fields.empty?
    WSApplication.message_box(
      "No result fields found for '#{selected_table_name}'.",
      'OK',
      nil,
      false
    )
    return false
  end

  puts "Found #{result_fields.length} result fields for '#{selected_table_name}'."

  selected_fields = get_user_field_selection_ui(selected_table_name, result_fields)

  if selected_fields.empty?
    puts "No fields selected for export from '#{selected_table_name}'. Skipping."
    return false
  end

  options = get_export_options_ui(selected_table_name)
  return false if options.nil?

  export_folder = options[:folder]
  calculate_stats = options[:calculate_stats]
  export_time_series = options[:export_time_series]
  export_summary = options[:export_summary]

  export_to_csv = !export_folder.empty? && (export_summary || export_time_series)

  if export_to_csv
    begin
      Dir.mkdir(export_folder) unless Dir.exist?(export_folder)
    rescue StandardError => e
      WSApplication.message_box(
        "Could not create directory '#{export_folder}': #{e.message}\n\nProceeding with statistics only.",
        'OK',
        nil,
        false
      )
      export_to_csv = false
    end
  end

  timestamp = Time.now.strftime('%Y%m%d_%H%M%S')

  puts "Processing #{selected_fields.length} fields..."

  total_objects_processed = 0
  field_summaries = []

  begin
    selected_fields.each_with_index do |field_name, field_index|
      field_start_time = Time.now
      puts "\nProcessing field #{field_index + 1}/#{selected_fields.length}: #{field_name}"

      summary_file_path = nil
      timeseries_file_path = nil

      if export_to_csv
        summary_file_path = File.join(export_folder, "#{selected_table_name}_#{field_name}_summary_#{timestamp}.csv") if export_summary
        timeseries_file_path = File.join(export_folder, "#{selected_table_name}_#{field_name}_timeseries_#{timestamp}.csv") if export_time_series
      end

      objects_processed = 0

      if export_to_csv
        summary_csv = nil
        timeseries_csv = nil

        begin
          if summary_file_path
            File.open(summary_file_path, "w") do |f|
              summary_csv = CSV.new(f)
              summary_headers = ['Object_ID', 'Field', 'Count', 'Min', 'Max', 'Mean', 'StdDev', 'Sum']
              summary_csv << summary_headers

              process_field_for_table(cn, selected_table_name, field_name, timesteps, time_interval,
                                     summary_csv, timeseries_file_path, calculate_stats, objects_processed)
            end
          end
        ensure
          summary_csv.close if summary_csv && !summary_csv.closed?
        end

        if timeseries_file_path
          File.open(timeseries_file_path, "w") do |f|
            timeseries_csv = CSV.new(f)
            timeseries_headers = ['Object_ID'] + timesteps.map { |ts| ts.strftime('%Y-%m-%d %H:%M:%S') }
            timeseries_csv << timeseries_headers
          end
        end
      else
        objects_processed = process_field_for_table(cn, selected_table_name, field_name, timesteps, time_interval,
                                                   nil, nil, calculate_stats, objects_processed)
      end

      field_time = Time.now - field_start_time
      field_summary = "Field '#{field_name}': #{objects_processed} objects in #{'%.2f' % field_time}s"

      field_summary += "\n  Summary: #{summary_file_path}" if summary_file_path
      field_summary += "\n  Time series: #{timeseries_file_path}" if timeseries_file_path

      field_summaries << field_summary
      total_objects_processed += objects_processed

      puts "\n#{field_summary}"
    end
  rescue StandardError => e
    puts "Error processing fields: #{e.message}"
  end

  time_spent = Time.now - start_time

  summary_message = "Table: #{selected_table_name}\n"
  summary_message += "Total objects processed: #{total_objects_processed}\n"
  summary_message += "Processing time: #{'%.2f' % time_spent} seconds\n\n"
  summary_message += "Fields processed:\n"
  field_summaries.each { |fs| summary_message += "- #{fs}\n" }

  WSApplication.message_box(summary_message, 'OK', nil, false)

  true
end

# Helper to process field for table
def process_field_for_table(cn, table_name, field_name, timesteps, time_interval,
                           summary_csv, timeseries_file_path, calculate_stats, objects_processed)
  count = 0
  begin
    row_objects = cn.row_objects(table_name)

    row_objects.each do |obj|
      next unless obj.respond_to?(:selected) && obj.selected

      obj_id = obj.respond_to?(:id) ? obj.id : "Object_#{count + 1}"

      begin
        results = obj.results(field_name) if obj.respond_to?(:results)
        next unless results && results.count > 0

        values = results.map { |r| r.to_f.finite? ? r.to_f : 0.0 }

        min_val = values.min
        max_val = values.max
        mean_val = calculate_mean(values)
        std_dev = calculate_std_dev(values, mean_val)
        sum_val = values.sum

        summary_row = [obj_id, field_name, values.count, min_val.round(6), max_val.round(6),
                      mean_val.round(6), std_dev ? std_dev.round(6) : 0.0, sum_val.round(6)]

        summary_csv << summary_row if summary_csv

        if calculate_stats
          puts "#{table_name}: #{'%-12s' % obj_id} | #{'%-16s' % field_name} | " \
               "End: #{safe_format(values.last, 4)} | Mean: #{safe_format(mean_val, 4)} | " \
               "Max: #{safe_format(max_val, 4)} | Min: #{safe_format(min_val, 4)} | Steps: #{'%6d' % values.count}"
        end

        if timeseries_file_path
          File.open(timeseries_file_path, "a") do |f|
            csv = CSV.new(f)
            timeseries_row = [obj_id] + values.map { |v| v.round(6) }
            csv << timeseries_row
          end
        end

        count += 1
        puts "Progress: #{count} objects processed" if count % 50 == 0

      rescue NoMethodError, StandardError => e
        puts "Warning: Could not process results for object '#{obj_id}', field '#{field_name}': #{e.message}"
      end
    end
  rescue StandardError => e
    puts "Error processing table '#{table_name}': #{e.message}"
  end

  count
end

# --- UI-based table selection ---
def get_user_table_selection_ui(available_tables)
  table_prompts = [["Select ALL TABLES", 'Boolean', false]]

  available_tables.each do |table|
    table_prompts << [table, 'Boolean', false]
  end

  user_selections = WSApplication.prompt(
    "Select Tables to Export Results",
    table_prompts,
    false
  )

  return [] if user_selections.nil?

  selected_tables = []
  select_all = user_selections[0]

  available_tables.each_with_index do |table, index|
    if select_all || user_selections[index + 1]
      selected_tables << table
    end
  end

  selected_tables
end

# --- Main Script Logic ---
begin
  overall_start_time = Time.now
  puts "Starting Results Field Exporter at #{overall_start_time}"
  puts "=" * 60

  cn = nil
  begin
    cn = WSApplication.current_network
    raise "No network loaded." if cn.nil?
  rescue StandardError => e
    WSApplication.message_box(
      "Could not access current network.\n\nPlease ensure a network is loaded and try again.",
      'OK',
      nil,
      false
    )
    raise e
  end

  begin
    timesteps = cn.list_timesteps
    if timesteps.nil? || timesteps.empty?
      WSApplication.message_box(
        "No timesteps found.\n\nPlease ensure you have simulation results loaded.",
        'OK',
        nil,
        false
      )
      raise "No timesteps available"
    end

    ts_count = timesteps.count
    time_interval = 0

    time_interval = (timesteps[1] - timesteps[0]).abs if ts_count > 1

    sim_info = "Simulation Information:\n"
    sim_info += "- Total timesteps: #{ts_count}\n"
    sim_info += "- Start time: #{timesteps.first}\n"
    sim_info += "- End time: #{timesteps.last}\n"
    sim_info += "- Time interval: %.4f seconds (%.4f minutes)" % [time_interval, time_interval / 60.0] if ts_count > 1

    puts sim_info

  rescue StandardError => e
    WSApplication.message_box(
      "Could not get timesteps: #{e.message}",
      'OK',
      nil,
      false
    )
    raise e
  end

  available_tables_with_results = get_result_fields_from_network(cn)

  if available_tables_with_results.empty?
    WSApplication.message_box(
      "No result fields found in the network.\n\nPlease ensure you have simulation results loaded.",
      'OK',
      nil,
      false
    )
    raise "No result fields found"
  end

  info_message = "Results Export Ready\n\n"
  info_message += "Found result fields in #{available_tables_with_results.keys.length} tables:\n"
  available_tables_with_results.each do |table, fields|
    info_message += "- #{table}: #{fields.length} fields\n"
  end
  info_message += "\nTime interval: %.4f seconds" % time_interval if ts_count > 1

  continue = WSApplication.message_box(
    info_message + "\n\nProceed with export?",
    'YESNO',
    nil,
    false
  )

  raise "User cancelled export" if continue == 'NO'

  table_names = available_tables_with_results.keys.sort
  total_tables_exported = 0
  continue_exporting = true

  while continue_exporting
    selected_tables = get_user_table_selection_ui(table_names)

    if selected_tables.empty?
      WSApplication.message_box("No tables selected.", 'OK', nil, false)
      break
    end

    puts "\nSelected tables: #{selected_tables.join(', ')}"

    tables_processed = 0
    selected_tables.each do |table_name|
      begin
        if process_single_table_results(cn, table_name, available_tables_with_results, timesteps, time_interval)
          total_tables_exported += 1
          tables_processed += 1
        end
      rescue StandardError => e
        puts "Error processing table '#{table_name}': #{e.message}"
        error_choice = WSApplication.message_box(
          "Error processing table '#{table_name}':\n#{e.message}\n\nContinue with remaining tables?",
          'YESNO',
          nil,
          false
        )
        break if error_choice == 'NO'
      end
    end

    batch_message = "Batch complete!\n\nTables processed: #{tables_processed}"
    continue_choice = WSApplication.message_box(
      batch_message + "\n\nProcess more tables?",
      'YESNO',
      nil,
      false
    )

    continue_exporting = (continue_choice == 'YES')
  end

  overall_end_time = Time.now
  total_time_spent = overall_end_time - overall_start_time

  final_message = "Export Complete!\n\n"
  final_message += "Total tables exported: #{total_tables_exported}\n"
  final_message += "Total execution time: #{'%.2f' % total_time_spent} seconds"

  WSApplication.message_box(final_message, 'OK', nil, false)

  puts "\n#{'='*25} Script Complete #{'='*25}"
  puts "Total tables exported: #{total_tables_exported}"
  puts "Total execution time: #{'%.2f' % total_time_spent} seconds"

rescue StandardError => e
  puts "Fatal error: #{e.message}"
  puts e.backtrace.join("\n")
  WSApplication.message_box("Script error: #{e.message}", 'OK', nil, false) rescue nil
ensure
  puts "Script execution finished at #{Time.now}"
end
