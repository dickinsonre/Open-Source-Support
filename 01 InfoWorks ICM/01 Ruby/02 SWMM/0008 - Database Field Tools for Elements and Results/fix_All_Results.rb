# frozen_string_literal: true

# Purpose: Collect and summarize result field values from network tables
# Inputs: Network tables with result_fields, row objects
# Outputs: Console output with result field statistics
# Type: EX Script (table_info.results_fields)
# Hardening: nil-safety, table_info validation, has_field? checks, zero-guard division

begin
  net = WSApplication.current_network
  raise "Network is nil" if net.nil?

  numeric_fields = Hash.new { |h, k| h[k] = Hash.new { |h, k| h[k] = [] } }
  non_numeric_fields = Hash.new(0)

  puts "[#{Time.now.strftime('%H:%M:%S')}] Starting result fields collection"

  table_count = 0
  net.tables&.each do |table|
    begin
      table_count += 1
      puts "Processing table: #{table.name}"
      net.row_objects(table.name)&.each do |row_object|
        next if row_object.nil? || row_object.table_info.nil?
        if row_object.table_info.results_fields
          row_object.table_info.results_fields.each do |field|
            puts "Table: #{table.name} Field: #{field.name}"
            if row_object.respond_to?(:has_field?) && row_object.has_field?(field.name)
              value = row_object[field.name]
              if value.is_a?(Numeric)
                numeric_fields[table.name][field.name] << value
              else
                non_numeric_fields[value] += 1
              end
            elsif !row_object.respond_to?(:has_field?)
              value = row_object[field.name] rescue nil
              if value.is_a?(Numeric)
                numeric_fields[table.name][field.name] << value
              elsif !value.nil?
                non_numeric_fields[value] += 1
              end
            else
              puts "Field #{field.name} does not exist in table: #{table.name}"
            end
          end
        else
          puts "No results fields for table: #{table.name}"
        end
      end
    rescue => e
      puts "[#{Time.now.strftime('%H:%M:%S')}] Error processing table #{table.name}: #{e.message}"
    end
  end

  puts "[#{Time.now.strftime('%H:%M:%S')}] Summary of numeric fields:"
  numeric_fields.each do |table_name, fields|
    fields.each do |field_name, values|
      next if values.empty?
      count = values.size
      sum = values.sum.to_f
      max_value = values.max
      min_value = values.min
      mean = count > 0 ? sum / count : 0.0
      puts format("Table: %-35s Field: %-30s Count: %-15d Mean: %-15.4f Max: %-15.4f Min: %-15.4f", table_name, field_name, count, mean, max_value, min_value)
    end
  end

  puts "[#{Time.now.strftime('%H:%M:%S')}] Summary of non-numeric fields:"
  non_numeric_fields.each do |value, count|
    puts "#{value}: #{count}"
  end

  puts "[#{Time.now.strftime('%H:%M:%S')}] Completed: processed #{table_count} tables"

rescue => e
  puts "[#{Time.now.strftime('%H:%M:%S')}] Fatal error: #{e.message}"
  puts e.backtrace.first(5)
ensure
  puts "[#{Time.now.strftime('%H:%M:%S')}] Script ended"
end
