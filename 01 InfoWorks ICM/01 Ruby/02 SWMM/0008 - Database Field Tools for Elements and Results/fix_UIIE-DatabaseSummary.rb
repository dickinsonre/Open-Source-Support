# frozen_string_literal: true
begin
  db = WSApplication.current_database
  raise "Database is nil" if db.nil?
  puts "[#{Time.now.strftime('%H:%M:%S')}] Database summary"
  roots = db.root_model_objects&.length || 0
  puts "Root objects: #{roots}"
  total = 0
  db.root_model_objects&.each { |r| total += (r.children&.length || 0) }
  puts "Total child objects: #{total}"
  puts "[#{Time.now.strftime('%H:%M:%S')}] Completed"
rescue => e
  puts "[#{Time.now.strftime('%H:%M:%S')}] Error: #{e.message}"
ensure
  puts "[#{Time.now.strftime('%H:%M:%S')}] Script ended"
end
