# frozen_string_literal: true
begin
  net = WSApplication.current_network
  raise "Network is nil" if net.nil?
  puts "[#{Time.now.strftime('%H:%M:%S')}] Preparing to change node/link IDs"

  val = WSApplication.prompt("Confirm ID change", [['Proceed', 'Boolean', false]], false)
  raise "User cancelled" if val.nil?

  puts "ID change initiated (dry run - implement in main script)"
  puts "[#{Time.now.strftime('%H:%M:%S')}] Completed"
rescue => e
  puts "[#{Time.now.strftime('%H:%M:%S')}] Error: #{e.message}"
ensure
  puts "[#{Time.now.strftime('%H:%M:%S')}] Script ended"
end
