# frozen_string_literal: true
# List all result fields in InfoWorks 2D zone tables
#
# HARDENING APPLIED:
#   - Added frozen_string_literal pragma
#   - Wrapped in begin/rescue/ensure
#   - Validates network is open
#   - Nil-safety for table and field access
#   - Safe iteration over timesteps and results

begin
  puts "[#{Time.now}] Starting InfoWorks 2D parameter statistics"

  cn = WSApplication.current_network
  if cn.nil?
    puts "[#{Time.now}] ERROR: No network is currently open"
    exit 1
  end

  puts "Tables and their result fields in this ICM InfoWorks Run"
  cn.tables&.each do |table|
    results_array = []
    found_results = false

    cn.row_object_collection(table.name)&.each do |row_object|
      next unless row_object.table_info&.results_fields && !found_results

      row_object.table_info.results_fields.each do |field|
        results_array << field.name
      end
      found_results = true
      break
    end

    unless results_array.empty?
      puts "Table: #{table.name.upcase}"
      results_array.each do |field|
        puts "Result field: #{field}"
      end
      puts ""
    end
  end

  ts = cn.list_timesteps
  ts_size = ts&.count || 0
  puts "Time step size: #{ts_size}"

  if ts && !ts.empty?
    puts ts.map(&:abs).join(", ")
    time_interval = (ts[1] - ts[0]).abs
    puts "Time interval: %.4f seconds or %.4f minutes" % [time_interval, time_interval / 60.0]
  end

  puts "[#{Time.now}] Analysis complete"

rescue => e
  puts "[#{Time.now}] ERROR: #{e.class} - #{e.message}"
  puts e.backtrace.first(5).join("\n")
  exit 1
ensure
  puts "[#{Time.now}] Script execution completed"
end
