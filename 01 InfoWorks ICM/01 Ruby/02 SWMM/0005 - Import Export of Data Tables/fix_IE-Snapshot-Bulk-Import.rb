# frozen_string_literal: true
# ---------------------------------------------------------------------------
# fix_IE-Snapshot-Bulk-Import.rb
#
# Purpose : Bulk-import every .isfc / .isf snapshot file under a directory
#           into a Collection Network in InfoAsset Manager via Exchange.
# Inputs  : DB_URL, NETWORK_ID, SOURCE_DIR, EXTENSIONS list.
# Outputs : Imports rows into the chosen network and commits.
# Type    : EX (Exchange) script.
# Hardening:
#   * frozen_string_literal pragma
#   * Validates database opens, network exists, source dir exists
#   * begin/rescue/ensure around main logic; commit only if no errors
#   * Per-file rescue so one bad file doesn't abort the run
#   * Timestamped logging
# ---------------------------------------------------------------------------

DB_URL     = 'localhost:40000/IA_2020.2'
NETWORK_ID = 32
SOURCE_DIR = 'C:/Temp/Data/'
EXTENSIONS = 'isfc,isf'

def log(msg); puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] #{msg}"; end

begin
  raise "Source directory does not exist: #{SOURCE_DIR}" unless File.directory?(SOURCE_DIR)

  db = WSApplication.open(DB_URL, false)
  raise "Could not open database #{DB_URL}" if db.nil?

  nw = db.model_object_from_type_and_id('Collection Network', NETWORK_ID)
  raise "Collection Network ID #{NETWORK_ID} not found." if nw.nil?

  on = nw.open
  nw.update

  options = {
    'AllowDeletes'                      => true,
    'ImportGeoPlanPropertiesAndThemes'  => false,
    'UpdateExistingObjectsFoundByID'    => false,
    'UpdateExistingObjectsFoundByUID'   => true,
    'ImportImageFiles'                  => true
  }

  log "Data location: #{SOURCE_DIR}"
  imported = 0; failed = 0
  Dir.glob(File.join(SOURCE_DIR, "**/*.{#{EXTENSIONS}}")).each do |fname|
    begin
      log "Importing #{fname}"
      on.snapshot_import_ex(fname, options)
      imported += 1
    rescue StandardError => fe
      failed += 1
      log "  Skipping #{fname}: #{fe.message}"
    end
  end

  log "Import phase complete. imported=#{imported} failed=#{failed}"
  if imported > 0 && failed == 0
    nw.commit("#{EXTENSIONS} data imported from #{SOURCE_DIR}")
    log 'Network committed.'
  else
    log 'Skipping commit due to errors or zero imports.'
  end
rescue StandardError => e
  log "Aborted: #{e.message}"
ensure
  log 'fix_IE-Snapshot-Bulk-Import.rb finished.'
end
