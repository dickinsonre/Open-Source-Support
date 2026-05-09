# frozen_string_literal: true
# ---------------------------------------------------------------------------
# fix_IE-csv_changes.rb
#
# Purpose : Generate a CSV showing the differences between two commits of a
#           Collection Network using net.csv_changes.
# Inputs  : DB_URL, NETWORK_ID, COMMIT_FROM, COMMIT_TO, OUTPUT_CSV.
# Outputs : CSV file at OUTPUT_CSV.
# Type    : EX (Exchange) script.
# Hardening:
#   * frozen_string_literal pragma
#   * Validates database opens and network exists
#   * Ensures output directory exists
#   * begin/rescue/ensure with timestamped logging
# ---------------------------------------------------------------------------

require 'fileutils'

DB_URL      = 'localhost:40000/database'
NETWORK_ID  = 20
COMMIT_FROM = 100
COMMIT_TO   = 120
OUTPUT_CSV  = 'C:\\temp\\changes.csv'

def log(msg); puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] #{msg}"; end

begin
  db = WSApplication.open(DB_URL)
  raise "Could not open database #{DB_URL}" if db.nil?

  net = db.model_object_from_type_and_id('Collection Network', NETWORK_ID)
  raise "Collection Network ID #{NETWORK_ID} not found." if net.nil?

  out_dir = File.dirname(OUTPUT_CSV)
  FileUtils.mkdir_p(out_dir) unless Dir.exist?(out_dir)

  log "Writing changes between commits #{COMMIT_FROM}..#{COMMIT_TO} to #{OUTPUT_CSV}..."
  net.csv_changes(COMMIT_FROM, COMMIT_TO, OUTPUT_CSV)
  log 'csv_changes complete.'
rescue StandardError => e
  log "Aborted: #{e.message}"
ensure
  log 'fix_IE-csv_changes.rb finished.'
end
