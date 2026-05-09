# frozen_string_literal: true
# ---------------------------------------------------------------------------
# fix_UI-CSV_export.rb
#
# Purpose : Export the entire current network to CSV via csv_export.
#           (Fixes the missing comma in the original argument list.)
# Inputs  : Active current_network.
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

  exp_options = {}
  FileUtils.mkdir_p(File.dirname(OUT_PATH)) unless Dir.exist?(File.dirname(OUT_PATH))

  log "Exporting network to #{OUT_PATH}..."
  nw.csv_export(OUT_PATH, exp_options)
  log 'CSV export complete.'
rescue StandardError => e
  log "Aborted: #{e.message}"
ensure
  log 'fix_UI-CSV_export.rb finished.'
end
