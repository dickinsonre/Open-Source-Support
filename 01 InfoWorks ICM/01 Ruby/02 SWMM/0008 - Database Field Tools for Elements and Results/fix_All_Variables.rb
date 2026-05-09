# frozen_string_literal: true

# Purpose: Collect all row objects and field values for validation
# Inputs: Network tables, row objects, fields
# Outputs: Array $validation with row objects and field values
# Type: EX Script (diagnostic/validation)
# Hardening: nil-safety, frozen global, array bounds checking

begin
  raise "Network is nil" if WSApplication.current_network.nil?

  $validation = []
  puts "[#{Time.now.strftime('%H:%M:%S')}] Starting validation data collection"

  table_count = 0
  WSApplication.current_network.tables&.each do |table|
    begin
      table_count += 1
      table.fields&.each do |field|
        WSApplication.current_network.row_objects(table.name)&.each do |row_object|
          next if row_object.nil?
          $validation << row_object
          val = row_object[field.name]
          $validation << (val.nil? ? 'nil' : val)
        end
      end
    rescue => e
      puts "[#{Time.now.strftime('%H:%M:%S')}] Error processing table #{table.name}: #{e.message}"
    end
  end

  puts "[#{Time.now.strftime('%H:%M:%S')}] Validation array size: #{$validation.size}"
  puts "[#{Time.now.strftime('%H:%M:%S')}] Sample (first 20 entries):"
  $validation.first(20).each_with_index { |v, i| puts "  [#{i}] #{v.class}: #{v.to_s[0..50]}" }

  puts "[#{Time.now.strftime('%H:%M:%S')}] Completed: collected #{table_count} tables"

rescue => e
  puts "[#{Time.now.strftime('%H:%M:%S')}] Fatal error: #{e.message}"
  puts e.backtrace.first(5)
ensure
  puts "[#{Time.now.strftime('%H:%M:%S')}] Script ended"
end
