# frozen_string_literal: true
begin
  net = WSApplication.current_network
  raise "Network is nil" if net.nil?
  puts "[#{Time.now.strftime('%H:%M:%S')}] Finding InfoWorks HW network elements"

  count = 0
  net.tables&.each do |t|
    next unless t.name.to_s.start_with?('hw_')
    net.row_objects(t.name)&.each { |ro| count += 1 if !ro.nil? }
  end

  puts "Total HW elements: #{count}"
  puts "[#{Time.now.strftime('%H:%M:%S')}] Completed"
rescue => e
  puts "[#{Time.now.strftime('%H:%M:%S')}] Error: #{e.message}"
ensure
  puts "[#{Time.now.strftime('%H:%M:%S')}] Script ended"
end
