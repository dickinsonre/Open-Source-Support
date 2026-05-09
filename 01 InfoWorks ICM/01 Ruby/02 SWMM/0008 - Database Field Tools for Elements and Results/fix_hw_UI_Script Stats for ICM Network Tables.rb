# frozen_string_literal: true
begin
  net = WSApplication.current_network
  raise "Network is nil" if net.nil?
  puts "[#{Time.now.strftime('%H:%M:%S')}] InfoWorks HW table statistics"

  net.tables&.each do |t|
    next unless t.name.to_s.start_with?('hw_')
    count = net.row_objects(t.name)&.length || 0
    puts "#{t.name}: #{count} rows"
  end

  puts "[#{Time.now.strftime('%H:%M:%S')}] Completed"
rescue => e
  puts "[#{Time.now.strftime('%H:%M:%S')}] Error: #{e.message}"
ensure
  puts "[#{Time.now.strftime('%H:%M:%S')}] Script ended"
end
