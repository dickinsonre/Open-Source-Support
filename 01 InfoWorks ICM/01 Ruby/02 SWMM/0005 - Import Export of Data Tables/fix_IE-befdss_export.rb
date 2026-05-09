# frozen_string_literal: true
# ---------------------------------------------------------------------------
# fix_IE-befdss_export.rb
#
# Purpose : Export a BEFDSS XML file for a given Collection Network using
#           network.befdss_export.
# Inputs  : DB_URL, NETWORK_ID, output XML path, log file path.
# Outputs : XML file at FILE_PATH and log at LOG_PATH.
# Type    : EX (Exchange) script.
# Hardening:
#   * frozen_string_literal pragma
#   * Validates database opens and network exists
#   * Ensures output and log directories exist before export
#   * begin/rescue/ensure with timestamped logging
# ---------------------------------------------------------------------------

require 'fileutils'

DB_URL     = '//localhost:40000/MasterDatabase'
NETWORK_ID = 123
LOG_PATH   = 'C:\\temp\\log.txt'
FILE_PATH  = 'C:\\temp\\export.xml'

def log(msg); puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] #{msg}"; end

begin
  db = WSApplication.open(DB_URL, false)
  raise "Could not open database #{DB_URL}" if db.nil?

  nw = db.model_object_from_type_and_id('Collection Network', NETWORK_ID)
  raise "Collection Network ID #{NETWORK_ID} not found." if nw.nil?

  [File.dirname(LOG_PATH), File.dirname(FILE_PATH)].each do |dir|
    FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
  end

  log "Running befdss_export to #{FILE_PATH}..."
  # nw.befdss_export(Filename, Type, Images, SelectedSurveysOnly, LogFile)
  nw.befdss_export(FILE_PATH, 'DP', true, false, LOG_PATH)
  log 'BEFDSS export complete.'
rescue StandardError => e
  log "Aborted: #{e.message}"
ensure
  log 'fix_IE-befdss_export.rb finished.'
end
