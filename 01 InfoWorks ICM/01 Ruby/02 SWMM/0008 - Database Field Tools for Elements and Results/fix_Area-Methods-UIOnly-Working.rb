# frozen_string_literal: true
begin
  net = WSApplication.current_network
  raise "Network is nil" if net.nil?
  puts "[#{Time.now.strftime('%H:%M:%S')}] Area methods UI script"

  total_area = 0.0
  net.row_objects('hw_subcatchment')&.each do |s|
    next if s.nil?
    area = s.respond_to?(:area) ? s.area.to_f : 0.0
    total_area += area
  end

  puts "Total subcatchment area: #{total_area.round(4)}"
  puts "[#{Time.now.strftime('%H:%M:%S')}] Completed"
rescue => e
  puts "[#{Time.now.strftime('%H:%M:%S')}] Error: #{e.message}"
ensure
  puts "[#{Time.now.strftime('%H:%M:%S')}] Script ended"
end
