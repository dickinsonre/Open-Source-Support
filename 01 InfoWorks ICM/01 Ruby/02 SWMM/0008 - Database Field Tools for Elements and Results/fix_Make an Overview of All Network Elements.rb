# frozen_string_literal: true
begin
  net = WSApplication.current_network
  raise "Network is nil" if net.nil?
  puts "[#{Time.now.strftime('%H:%M:%S')}] Network overview"
  puts "=" * 50

  net.tables&.each do |t|
    count = net.row_objects(t.name)&.length || 0
    puts "#{t.name}: #{count}" if count > 0
  end

  puts "=" * 50
  puts "[#{Time.now.strftime('%H:%M:%S')}] Completed"
rescue => e
  puts "[#{Time.now.strftime('%H:%M:%S')}] Error: #{e.message}"
ensure
  puts "[#{Time.now.strftime('%H:%M:%S')}] Script ended"
end
