# frozen_string_literal: true
begin
  net = WSApplication.current_network
  raise "Network is nil" if net.nil?
  puts "[#{Time.now.strftime('%H:%M:%S')}] SWMM run parameters summary"

  net.row_objects('sw_sim_parameters')&.each do |p|
    next if p.nil?
    puts "Simulation: #{p.respond_to?(:name) ? p.name : p.id}"
  end

  puts "[#{Time.now.strftime('%H:%M:%S')}] Completed"
rescue => e
  puts "[#{Time.now.strftime('%H:%M:%S')}] Error: #{e.message}"
ensure
  puts "[#{Time.now.strftime('%H:%M:%S')}] Script ended"
end
