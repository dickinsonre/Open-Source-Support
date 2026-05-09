# frozen_string_literal: true
# ---------------------------------------------------------------------------
# fix_hw_UI-GIS_export.rb
#
# Purpose : Export hw_node, hw_conduit and hw_subcatchment to a Shapefile
#           folder via cn.GIS_export.  User picks the destination folder.
# Inputs  : Active current_network (InfoWorks); folder picked in prompt.
# Outputs : SHP files in the chosen folder.
# Type    : UI script.
# Hardening:
#   * frozen_string_literal pragma
#   * Validates current_network and prompt result
#   * Validates folder exists before exporting
#   * begin/rescue/ensure with timestamped logging
# ---------------------------------------------------------------------------

require 'fileutils'

def log(msg); puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] #{msg}"; end

begin
  cn = WSApplication.current_network
  raise 'No current network is open.' if cn.nil?

  network_name = cn.network_model_object.name rescue 'Unknown'
  log "Network: #{network_name}"

  export_tables = %w[hw_node hw_conduit hw_subcatchment]
  exp_options = {
    'ExportFlags'    => false,
    'SkipEmptyTables'=> false,
    'Tables'         => export_tables
  }

  val = WSApplication.prompt('Folder for the Export of ICM InfoWorks SHP Files', [
    ['Pick the Folder', 'String', nil, nil, 'FOLDER', 'Folder'],
    ['Export to GIS file via GIS_export method', 'String'],
    ['Export_tables = ["hw_node","hw_conduit","hw_subcatchment"]', 'String'],
    ['Formats: SHP,TAB,MIF,GDB', 'String']
  ], false)
  raise 'Prompt cancelled.' if val.nil?
  folder_path = val[0]
  raise 'No folder chosen.' if folder_path.nil? || folder_path.to_s.empty?

  FileUtils.mkdir_p(folder_path) unless Dir.exist?(folder_path)

  log "Exporting SHP files to #{folder_path}..."
  cn.GIS_export('SHP', exp_options, "#{folder_path}/")
  log 'GIS export complete.'
rescue StandardError => e
  log "Aborted: #{e.message}"
ensure
  log 'fix_hw_UI-GIS_export.rb finished.'
end
