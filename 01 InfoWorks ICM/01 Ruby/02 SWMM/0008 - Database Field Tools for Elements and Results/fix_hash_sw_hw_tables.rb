# frozen_string_literal: true
begin
  net = WSApplication.current_network
  raise "Network is nil" if net.nil?
  puts "[#{Time.now.strftime('%H:%M:%S')}] Building table hash"

  table_hash = {}
  net.tables&.each do |t|
    name = t.name.to_s
    table_hash[name] = { sw: name.start_with?('sw_'), hw: name.start_with?('hw_') }
  end

  puts "Total tables: #{table_hash.length}"
  puts "SW tables: #{table_hash.values.count { |h| h[:sw] }}"
  puts "HW tables: #{table_hash.values.count { |h| h[:hw] }}"
  puts "[#{Time.now.strftime('%H:%M:%S')}] Completed"
rescue => e
  puts "[#{Time.now.strftime('%H:%M:%S')}] Error: #{e.message}"
ensure
  puts "[#{Time.now.strftime('%H:%M:%S')}] Script ended"
end
