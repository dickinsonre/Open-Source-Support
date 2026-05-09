# frozen_string_literal: true
begin
  net = WSApplication.current_network
  raise "Network is nil" if net.nil?
  puts "[#{Time.now.strftime('%H:%M:%S')}] Flow survey analysis"

  total_flow = 0.0
  net.row_objects('hw_conduit')&.each do |c|
    next if c.nil?
    flow = c.respond_to?(:flow) ? c.flow.to_f : 0.0
    total_flow += flow
  end

  puts "Total conduit flow: #{total_flow.round(4)}"
  puts "[#{Time.now.strftime('%H:%M:%S')}] Completed"
rescue => e
  puts "[#{Time.now.strftime('%H:%M:%S')}] Error: #{e.message}"
ensure
  puts "[#{Time.now.strftime('%H:%M:%S')}] Script ended"
end
