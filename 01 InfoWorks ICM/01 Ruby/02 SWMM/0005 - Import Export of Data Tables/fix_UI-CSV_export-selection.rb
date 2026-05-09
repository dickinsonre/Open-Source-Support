# frozen_string_literal: true
# ---------------------------------------------------------------------------
# fix_UI-CSV_export-selection.rb
#
# Purpose : Build a selection of cams_cctv_survey rows in the current network
#           and export the selection to CSV via csv_export.
# Inputs  : Active current_network with cams_cctv_survey rows.
# Outputs : CSV file at OUT_PATH.
# Type    : UI script.
# Hardening:
#   * frozen_string_literal pragma
#   * Validates current_network not nil
#   * Ensures output directory exists
#   * begin/rescue/ensure with timestamped logging
# ---------------------------------------------------------------------------

require 'fileutils'

OUT_PATH = 'C:\\Temp\\network.csv'

def log(msg); puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] #{msg}"; end

begin
  nw = WSApplication.current_network
  raise 'No current network is open.' if nw.nil?

  nw.clear_selection
  count = 0
  nw.row_objects('cams_cctv_survey').each do |ro|
    next if ro.nil?
    ro.selected = true
    count += 1
  end
  log "Selected #{count} cams_cctv_survey rows."

  exp_options = { 'Selection Only' => true }

  FileUtils.mkdir_p(File.dirname(OUT_PATH)) unless Dir.exist?(File.dirname(OUT_PATH))

  log "Exporting selection to #{OUT_PATH}..."
  nw.csv_export(OUT_PATH, exp_options)
  log 'CSV export of selection complete.'
rescue StandardError => e
  log "Aborted: #{e.message}"
ensure
  log 'fix_UI-CSV_export-selection.rb finished.'
end
