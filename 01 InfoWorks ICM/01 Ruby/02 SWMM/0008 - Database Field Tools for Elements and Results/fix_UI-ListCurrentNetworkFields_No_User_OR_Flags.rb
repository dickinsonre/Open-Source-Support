# frozen_string_literal: true
begin
  net = WSApplication.current_network
  raise "Network is nil" if net.nil?
  puts "[#{Time.now.strftime('%H:%M:%S')}] Listing user/flag-free network fields"
  net.tables&.each do |table|
    puts "Table: #{table.name}"
    table.fields&.each do |f|
      name = f.name.to_s
      next if name.include?('user') || name.include?('flag')
      puts "  - #{name}"
    end
  end
  puts "[#{Time.now.strftime('%H:%M:%S')}] Completed"
rescue => e
  puts "[#{Time.now.strftime('%H:%M:%S')}] Error: #{e.message}"
ensure
  puts "[#{Time.now.strftime('%H:%M:%S')}] Script ended"
end
