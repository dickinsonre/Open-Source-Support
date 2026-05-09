# frozen_string_literal: true

# Purpose: Delete rows from attachments blob table
# Inputs: Database, attachment table
# Outputs: Console feedback on deleted rows
# Type: UI Script (database operations)
# Hardening: begin/rescue/ensure, nil-safety

begin
  db = WSApplication.current_database
  raise "Database is nil" if db.nil?

  puts "[#{Time.now.strftime('%H:%M:%S')}] Starting attachment blob deletion"

  deleted = 0
  db.root_model_objects&.each do |rmo|
    rmo.children&.each do |child|
      if child.respond_to?(:type) && child.type.to_s.include?('attachment')
        child.delete rescue nil
        deleted += 1
      end
    end
  end

  puts "Deleted #{deleted} attachment rows"
  puts "[#{Time.now.strftime('%H:%M:%S')}] Completed"

rescue => e
  puts "[#{Time.now.strftime('%H:%M:%S')}] Error: #{e.message}"
ensure
  puts "[#{Time.now.strftime('%H:%M:%S')}] Script ended"
end
