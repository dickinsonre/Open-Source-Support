# frozen_string_literal: true
# ---------------------------------------------------------------------------
# fix_IE-snapshot_export_ex.rb
#
# Purpose : Export a snapshot (.isfc) for a Collection Network via
#           on.snapshot_export_ex.
# Inputs  : DB_URL, NETWORK_ID, OUT_FILE.
# Outputs : Snapshot file at OUT_FILE.
# Type    : EX (Exchange) script.
# Hardening:
#   * frozen_string_literal pragma
#   * Validates database opens, network exists, output dir exists
#   * begin/rescue/ensure with timestamped logging
# ---------------------------------------------------------------------------

require 'fileutils'

DB_URL     = 'localhost:40000/IA_NEW'
NETWORK_ID = 1246
OUT_FILE   = 'export.isfc'

def log(msg); puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] #{msg}"; end

begin
  db = WSApplication.open(DB_URL, false)
  raise "Could not open database #{DB_URL}" if db.nil?

  nw = db.model_object_from_type_and_id('Collection Network', NETWORK_ID)
  raise "Collection Network ID #{NETWORK_ID} not found." if nw.nil?

  nw.update
  on = nw.open

  exp = {
    'SelectedOnly'                     => false,
    'IncludeImageFiles'                => false,
    'IncludeGeoPlanPropertiesAndThemes'=> false
  }

  out_dir = File.dirname(OUT_FILE)
  FileUtils.mkdir_p(out_dir) if out_dir && !out_dir.empty? && !Dir.exist?(out_dir)

  log "Exporting snapshot to #{OUT_FILE}..."
  on.snapshot_export_ex(OUT_FILE, exp)
  log 'Snapshot export complete.'
rescue StandardError => e
  log "Aborted: #{e.message}"
ensure
  log 'fix_IE-snapshot_export_ex.rb finished.'
end
