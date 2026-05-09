# frozen_string_literal: true
# ---------------------------------------------------------------------------
# fix_IE-befdss_import_cctv-BulkImport.rb
#
# Purpose : Walk a directory of BEFDSS XML files and import each as CCTV
#           survey data into a Collection Network via befdss_import_cctv.
# Inputs  : DB_URL, NETWORK_ID, SOURCE_DIR.
# Outputs : Per-file log .txt and updated network.
# Type    : EX (Exchange) script.
# Hardening:
#   * frozen_string_literal pragma
#   * Validates database, network, source dir
#   * Per-file rescue prevents one bad XML aborting the run
#   * begin/rescue/ensure with timestamped logging
# ---------------------------------------------------------------------------

DB_URL     = '//localhost:40000/MasterDatabase'
NETWORK_ID = 123
SOURCE_DIR = 'C:/source/'

def log(msg); puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] #{msg}"; end

begin
  raise "Source directory does not exist: #{SOURCE_DIR}" unless File.directory?(SOURCE_DIR)

  db = WSApplication.open(DB_URL, false)
  raise "Could not open database #{DB_URL}" if db.nil?

  nw = db.model_object_from_type_and_id('Collection Network', NETWORK_ID)
  raise "Collection Network ID #{NETWORK_ID} not found." if nw.nil?

  net = nw.open
  log "Data location: #{SOURCE_DIR}"
  ok = 0; bad = 0
  Dir.glob(File.join(SOURCE_DIR, '**/*.xml')).each do |fname|
    begin
      log_file = "log_#{File.basename(fname)}.txt"
      log "Importing #{fname}"
      net.befdss_import_cctv(fname, 'KT', false, false, 1, false, log_file)
      ok += 1
    rescue StandardError => fe
      bad += 1
      log "  Skipping #{fname}: #{fe.message}"
    end
  end
  log "Import done. ok=#{ok} failed=#{bad}"
rescue StandardError => e
  log "Aborted: #{e.message}"
ensure
  log 'fix_IE-befdss_import_cctv-BulkImport.rb finished.'
end
