# frozen_string_literal: true
begin
  db = WSApplication.current_database
  raise "Database is nil" if db.nil?
  puts "[#{Time.now.strftime('%H:%M:%S')}] Finding root model groups"
  roots = db.root_model_objects || []
  puts "Found #{roots.length} root model objects"
  roots&.each { |r| puts "  - #{r.respond_to?(:id) ? r.id : r.type}" }
  puts "[#{Time.now.strftime('%H:%M:%S')}] Completed"
rescue => e
  puts "[#{Time.now.strftime('%H:%M:%S')}] Error: #{e.message}"
ensure
  puts "[#{Time.now.strftime('%H:%M:%S')}] Script ended"
end
