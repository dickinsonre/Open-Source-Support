# frozen_string_literal: true
# ---------------------------------------------------------------------------
# fix_IE-befdss_import_cctv.rb
#
# Purpose : Import a single BEFDSS CCTV XML file into a Collection Network.
# Inputs  : DB_URL, NETWORK_ID, FILE_PATH (xml), LOG_PATH.
# Outputs : Network rows updated and log file written.
# Type    : EX (Exchange) script.
# Hardening:
#   * frozen_string_literal pragma
#   * Validates database, network, input XML
#   * begin/rescue/ensure with timestamped logging
# ---------------------------------------------------------------------------

DB_URL     = '//localhost:40000/MasterDatabase'
NETWORK_ID = 123
LOG_PATH   = 'C:\\temp\\log.txt'
FILE_PATH  = 'C:\\temp\\BEFDSS_01_01_DP.xml'

def log(msg); puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] #{msg}"; end

begin
  raise "Input XML not found: #{FILE_PATH}" unless File.exist?(FILE_PATH)

  db = WSApplication.open(DB_URL, false)
  raise "Could not open database #{DB_URL}" if db.nil?

  nw = db.model_object_from_type_and_id('Collection Network', NETWORK_ID)
  raise "Collection Network ID #{NETWORK_ID} not found." if nw.nil?

  log "Importing #{FILE_PATH}..."
  # nw.befdss_import_cctv(Filename, Flag, Images, MatchExisting, GenerateIDsFrom, DuplicateIDs, LogFile)
  nw.befdss_import_cctv(FILE_PATH, 'KT', true, false, 1, false, LOG_PATH)
  log 'CCTV BEFDSS import complete.'
rescue StandardError => e
  log "Aborted: #{e.message}"
ensure
  log 'fix_IE-befdss_import_cctv.rb finished.'
end
