# frozen_string_literal: true
# ---------------------------------------------------------------------------
# fix_IE-DashboardExport.rb
#
# Purpose : Open an InfoAsset Manager database, find a Dashboard model object
#           by path, refresh it from the network, and export to HTML.
# Inputs  : Database server URL (edit DB_URL), dashboard path, output file.
# Outputs : HTML file at OUT_PATH.
# Type    : EX (Exchange) script.
# Hardening:
#   * frozen_string_literal pragma
#   * Validates database opens, model object found, output dir exists
#   * begin/rescue/ensure with timestamped logging
# ---------------------------------------------------------------------------

DB_URL    = '//localhost:40000/database'
DASH_PATH = '>MASG~MasterGroup>AG~AssetGroup>DASH~Dashboard'
OUT_PATH  = 'c:\\temp\\Dashboard\\badger.html'

def log(msg); puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] #{msg}"; end

begin
  log "Opening database #{DB_URL}..."
  db = WSApplication.open(DB_URL, false)
  raise "Could not open database #{DB_URL}" if db.nil?

  mo = db.model_object(DASH_PATH)
  raise "Dashboard not found: #{DASH_PATH}" if mo.nil?

  out_dir = File.dirname(OUT_PATH)
  unless Dir.exist?(out_dir)
    log "Creating output directory #{out_dir}..."
    require 'fileutils'
    FileUtils.mkdir_p(out_dir)
  end

  log 'Refreshing dashboard with current values...'
  mo.update_dashboard
  log "Exporting dashboard to #{OUT_PATH}..."
  mo.export(OUT_PATH, 'html')
  log 'Dashboard export complete.'
rescue StandardError => e
  log "Aborted: #{e.message}"
ensure
  log 'fix_IE-DashboardExport.rb finished.'
end
