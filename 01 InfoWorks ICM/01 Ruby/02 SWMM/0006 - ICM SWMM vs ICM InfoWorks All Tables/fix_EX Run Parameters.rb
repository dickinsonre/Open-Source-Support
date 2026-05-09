# frozen_string_literal: true
# ---------------------------------------------------------------------------
# fix_EX Run Parameters.rb
#
# Purpose : Retrieve all read/write Run fields for a given Run ID and print
#           them as a hash.  Used to inspect simulation parameters.
# Inputs  : Hard-coded run_id (replace placeholder).  Active database via
#           WSApplication.open.
# Outputs : Console dump of {field => value} for the run.
# Type    : EX (Exchange) script - opens database from WSApplication.open.
# Hardening:
#   * frozen_string_literal pragma
#   * Validates database opens, run object exists
#   * begin/rescue/ensure around main logic
#   * Nil-safety on field reads
#   * Timestamped logging
# ---------------------------------------------------------------------------

def log(msg)
  puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] #{msg}"
end

def retrieve_run_parameters(run_id)
  database = WSApplication.open
  raise 'Could not open database via WSApplication.open.' if database.nil?

  simulation = database.model_object_from_type_and_id('Run', run_id)
  raise "Run with ID #{run_id.inspect} not found." if simulation.nil?

  parameters = {}
  database.list_read_write_run_fields.each do |field|
    parameters[field] = begin
      simulation[field]
    rescue StandardError
      nil
    end
  end
  parameters
end

begin
  # Replace this with an actual run id before running.
  run_id = nil # e.g. 12345
  raise 'Set run_id to a real Run object id before running.' if run_id.nil?

  log "Retrieving parameters for run #{run_id}..."
  params = retrieve_run_parameters(run_id)
  params.each { |k, v| puts "#{k}: #{v.inspect}" }
  log "Retrieved #{params.size} fields."
rescue StandardError => e
  log "Aborted: #{e.message}"
ensure
  log 'fix_EX Run Parameters.rb finished.'
end
