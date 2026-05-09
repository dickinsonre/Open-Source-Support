# frozen_string_literal: true
begin
  db = WSApplication.current_database
  raise "Database is nil" if db.nil?
  puts "[#{Time.now.strftime('%H:%M:%S')}] Listing database contents"
  count = 0
  db.root_model_objects&.each do |rmo|
    puts "Root: #{rmo.respond_to?(:id) ? rmo.id : rmo.type}"
    rmo.children&.each { |c| count += 1 }
  end
  puts "Total objects: #{count}"
  puts "[#{Time.now.strftime('%H:%M:%S')}] Completed"
rescue => e
  puts "[#{Time.now.strftime('%H:%M:%S')}] Error: #{e.message}"
ensure
  puts "[#{Time.now.strftime('%H:%M:%S')}] Script ended"
end
