# frozen_string_literal: true

# Purpose: Recursively count all database objects by type
# Inputs: Database root model objects
# Outputs: Console output with object counts per table type
# Type: EX Script (database.root_model_objects, mo.children recursion)
# Hardening: nil-safety, depth limit guard, type validation

DEPTH_LIMIT = 9999

def get_child_objects(mo, counts, depth)
  raise "Model object is nil" if mo.nil?
  depth += 1
  if depth >= DEPTH_LIMIT
    puts "[#{Time.now.strftime('%H:%M:%S')}] Depth limit of #{DEPTH_LIMIT} reached"
    return
  end

  mo_type = mo.respond_to?(:type) ? mo.type : 'unknown'
  counts[mo_type] = (counts[mo_type] || 0) + 1

  mo.children&.each { |cmo| get_child_objects(cmo, counts, depth) }
rescue => e
  puts "[#{Time.now.strftime('%H:%M:%S')}] Error processing object at depth #{depth}: #{e.message}"
end

begin
  user = ENV['USER'] || ENV['USERNAME'] || 'unknown'
  puts "[#{Time.now.strftime('%H:%M:%S')}] Starting database object count for user: #{user}"

  database = WSApplication.current_database
  raise "Database is nil" if database.nil?

  counts = Hash.new(0)
  depth = 0

  database.root_model_objects&.each do |rmo|
    begin
      get_child_objects(rmo, counts, depth)
    rescue => e
      puts "[#{Time.now.strftime('%H:%M:%S')}] Error processing root object: #{e.message}"
    end
  end

  puts "[#{Time.now.strftime('%H:%M:%S')}] Summary of object types:"
  counts.each do |table, count|
    table_name_without_master = table.to_s.gsub('Master', 'Primary')
    puts format("%s: %i object(s)", table_name_without_master, count)
  end

  puts "[#{Time.now.strftime('%H:%M:%S')}] Completed: counted #{counts.values.sum} total objects"

rescue => e
  puts "[#{Time.now.strftime('%H:%M:%S')}] Fatal error: #{e.message}"
  puts e.backtrace.first(5)
ensure
  puts "[#{Time.now.strftime('%H:%M:%S')}] Script ended"
end
