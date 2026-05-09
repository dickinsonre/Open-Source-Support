# frozen_string_literal: true
begin
  net = WSApplication.current_network
  raise "Network is nil" if net.nil?
  puts "[#{Time.now.strftime('%H:%M:%S')}] Updating blockage property IDs"
  count = 0
  net.row_objects('hw_blockage')&.each do |obj|
    next if obj.nil?
    obj.property_id ||= obj.id if obj.respond_to?(:property_id=)
    count += 1
  end
  puts "Updated #{count} blockage records"
  puts "[#{Time.now.strftime('%H:%M:%S')}] Completed"
rescue => e
  puts "[#{Time.now.strftime('%H:%M:%S')}] Error: #{e.message}"
ensure
  puts "[#{Time.now.strftime('%H:%M:%S')}] Script ended"
end
