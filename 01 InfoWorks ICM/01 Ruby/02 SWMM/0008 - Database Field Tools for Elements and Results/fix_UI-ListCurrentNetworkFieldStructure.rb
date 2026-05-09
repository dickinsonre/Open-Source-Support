# frozen_string_literal: true

# Purpose: List network field structure with types and metadata
# Inputs: Network, table structure
# Outputs: Formatted field structure output
# Type: UI Script
# Hardening: nil-safety, begin/rescue/ensure, field type validation

begin
  net = WSApplication.current_network
  raise "Network is nil" if net.nil?

  puts "[#{Time.now.strftime('%H:%M:%S')}] Network field structure:"

  net.tables&.each do |table|
    puts "\nTable: #{table.name}"
    table.fields&.each do |field|
      field_type = field.respond_to?(:field_type) ? field.field_type : 'unknown'
      puts "  - #{field.name}: #{field_type}"
    end
  end

  puts "\n[#{Time.now.strftime('%H:%M:%S')}] Completed"

rescue => e
  puts "[#{Time.now.strftime('%H:%M:%S')}] Error: #{e.message}"
ensure
  puts "[#{Time.now.strftime('%H:%M:%S')}] Script ended"
end
