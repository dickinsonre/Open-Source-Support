# frozen_string_literal: true

# Purpose: Count repair records in database
# Inputs: Network database objects
# Outputs: Console output with repair counts
# Type: UI Script
# Hardening: nil-safety, begin/rescue/ensure, type validation

begin
  net = WSApplication.current_network
  raise "Network is nil" if net.nil?

  puts "[#{Time.now.strftime('%H:%M:%S')}] Starting repair count"
  repair_count = 0

  database = WSApplication.current_database
  raise "Database is nil" if database.nil?

  database.root_model_objects&.each do |rmo|
    rmo.children&.each do |child|
      repair_count += 1 if child.respond_to?(:type) && child.type.to_s.include?('repair')
    end
  end

  puts "Total repairs found: #{repair_count}"
  puts "[#{Time.now.strftime('%H:%M:%S')}] Completed"

rescue => e
  puts "[#{Time.now.strftime('%H:%M:%S')}] Error: #{e.message}"
  puts e.backtrace.first(3)
ensure
  puts "[#{Time.now.strftime('%H:%M:%S')}] Script ended"
end
