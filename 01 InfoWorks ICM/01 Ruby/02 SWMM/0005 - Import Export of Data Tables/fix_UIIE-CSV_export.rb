# frozen_string_literal: true
# ---------------------------------------------------------------------------
# fix_UIIE-CSV_export.rb
#
# Purpose : Export the network to CSV via csv_export.  Detects whether the
#           script is running in the UI or Exchange (IE) context and picks
#           current_network or opens by id accordingly.
# Inputs  : OUT_PATH; if Exchange, NETWORK_ID below.
# Outputs : CSV file at OUT_PATH.
# Type    : UI/EX dual-mode script.
# Hardening:
#   * frozen_string_literal pragma
#   * Validates network not nil after retrieval
#   * Ensures output dir exists
#   * begin/rescue/ensure with timestamped logging
# ---------------------------------------------------------------------------

require 'fileutils'

OUT_PATH   = 'C:\\Temp\\network.csv'
NETWORK_ID = 2

def log(msg); puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] #{msg}"; end

begin
  if WSApplication.ui?
    net = WSApplication.current_network
    raise 'No current network is open.' if net.nil?
  else
    db = WSApplication.open
    raise 'Could not open database via WSApplication.open.' if db.nil?
    dbnet = db.model_object_from_type_and_id('Collection Network', NETWORK_ID)
    raise "Collection Network ID #{NETWORK_ID} not found." if dbnet.nil?
    net = dbnet.open
  end

  exp_options = {}
  FileUtils.mkdir_p(File.dirname(OUT_PATH)) unless Dir.exist?(File.dirname(OUT_PATH))

  log "Exporting to #{OUT_PATH}..."
  net.csv_export(OUT_PATH, exp_options)
  log 'CSV export complete.'
rescue StandardError => e
  log "Aborted: #{e.message}"
ensure
  log 'fix_UIIE-CSV_export.rb finished.'
end
