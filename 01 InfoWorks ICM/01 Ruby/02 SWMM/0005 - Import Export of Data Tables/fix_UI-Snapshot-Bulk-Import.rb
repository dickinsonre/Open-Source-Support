# frozen_string_literal: true
# ---------------------------------------------------------------------------
# fix_UI-Snapshot-Bulk-Import.rb
#
# Purpose : Bulk-import every .isfc/.isf file under a directory tree into
#           the current network.
# Inputs  : Active current_network; SOURCE_DIR and EXTENSIONS constants.
# Outputs : Imported rows.
# Type    : UI script.
# Hardening:
#   * frozen_string_literal pragma
#   * Validates current_network and source dir exist
#   * Per-file rescue to keep going
#   * begin/rescue/ensure with timestamped logging
# ---------------------------------------------------------------------------

SOURCE_DIR = 'C:/Temp/Data/'
EXTENSIONS = 'isfc,isf'

def log(msg); puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] #{msg}"; end

begin
  nw = WSApplication.current_network
  raise 'No current network is open.' if nw.nil?
  raise "Source directory does not exist: #{SOURCE_DIR}" unless File.directory?(SOURCE_DIR)

  options = {
    'AllowDeletes'                     => true,
    'ImportGeoPlanPropertiesAndThemes' => false,
    'UpdateExistingObjectsFoundByID'   => false,
    'UpdateExistingObjectsFoundByUID'  => true,
    'ImportImageFiles'                 => true
  }

  log "Data location: #{SOURCE_DIR}"
  ok = 0; bad = 0
  Dir.glob(File.join(SOURCE_DIR, "**/*.{#{EXTENSIONS}}")).each do |fname|
    begin
      log "Importing #{fname}"
      nw.snapshot_import_ex(fname, options)
      ok += 1
    rescue StandardError => fe
      bad += 1
      log "  Skipping #{fname}: #{fe.message}"
    end
  end
  log "Import complete. ok=#{ok} failed=#{bad}"
rescue StandardError => e
  log "Aborted: #{e.message}"
ensure
  log 'fix_UI-Snapshot-Bulk-Import.rb finished.'
end
