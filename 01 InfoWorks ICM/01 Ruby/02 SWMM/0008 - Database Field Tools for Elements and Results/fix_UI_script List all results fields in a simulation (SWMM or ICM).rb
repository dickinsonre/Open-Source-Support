# frozen_string_literal: true
begin
  net = WSApplication.current_network
  raise "Network is nil" if net.nil?
  puts "[#{Time.now.strftime('%H:%M:%S')}] Listing all result fields"
  count = 0
  net.tables&.each do |t|
    net.row_objects(t.name)&.each do |ro|
      next if ro.nil? || ro.table_info.nil?
      ro.table_info.results_fields&.each { |f| puts "#{t.name}: #{f.name}"; count += 1 }
    end
  end
  puts "Total result fields: #{count}"
  puts "[#{Time.now.strftime('%H:%M:%S')}] Completed"
rescue => e
  puts "[#{Time.now.strftime('%H:%M:%S')}] Error: #{e.message}"
ensure
  puts "[#{Time.now.strftime('%H:%M:%S')}] Script ended"
end
