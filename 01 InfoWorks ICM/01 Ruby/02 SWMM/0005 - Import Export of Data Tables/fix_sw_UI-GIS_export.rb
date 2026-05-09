# frozen_string_literal: true
# ---------------------------------------------------------------------------
# fix_sw_UI-GIS_export.rb
#
# Purpose : Export sw_node, sw_conduit and sw_subcatchment to a Shapefile
#           folder via nw.GIS_export.
# Inputs  : Active current_network (ICM SWMM); OUT_DIR constant.
# Outputs : SHP files in OUT_DIR.
# Type    : UI script.
# Hardening:
#   * frozen_string_literal pragma
#   * Validates current_network not nil
#   * Ensures OUT_DIR exists before exporting
#   * begin/rescue/ensure with timestamped logging
# ---------------------------------------------------------------------------

require 'fileutils'

OUT_DIR = 'C:\\Temp\\ICM_Ruby_Network\\InfoSWMM'

def log(msg); puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] #{msg}"; end

begin
  nw = WSApplication.current_network
  raise 'No current network is open.' if nw.nil?

  export_tables = %w[sw_node sw_conduit sw_subcatchment]
  exp_options = {
    'ExportFlags'     => false,
    'SkipEmptyTables' => false,
    'Tables'          => export_tables
  }

  FileUtils.mkdir_p(OUT_DIR) unless Dir.exist?(OUT_DIR)

  log "Exporting SHP to #{OUT_DIR}..."
  nw.GIS_export('SHP', exp_options, OUT_DIR)
  log 'GIS export complete.'
rescue StandardError => e
  log "Aborted: #{e.message}"
ensure
  log 'fix_sw_UI-GIS_export.rb finished.'
end
