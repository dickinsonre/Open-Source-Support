# frozen_string_literal: true

# Purpose: List all network table fields
# Inputs: Network, tables
# Outputs: Console table with field names per table
# Type: UI Script
# Hardening: frozen strings, begin/rescue/ensure, nil-safety

begin
  net = WSApplication.current_network
  raise "Network is nil" if net.nil?

  puts "[#{Time.now.strftime('%H:%M:%S')}] Listing network fields"

  net.tables&.each do |table|
    puts "Table: #{table.name}"
    table.fields&.each { |field| puts "  - #{field.name}" }
  end

  puts "[#{Time.now.strftime('%H:%M:%S')}] Completed"

rescue => e
  puts "[#{Time.now.strftime('%H:%M:%S')}] Error: #{e.message}"
ensure
  puts "[#{Time.now.strftime('%H:%M:%S')}] Script ended"
end
