# frozen_string_literal: true
# ---------------------------------------------------------------------------
# fix_UI-snapshot_export_ex.rb
#
# Purpose : Export selected cams_cctv_survey + cams_manhole_survey rows of
#           the current network to a snapshot (.isfc) chosen via Save-As
#           dialog using snapshot_export_ex.
# Inputs  : Active current_network; user picks output via file_dialog.
# Outputs : .isfc snapshot file.
# Type    : UI script.
# Hardening:
#   * frozen_string_literal pragma
#   * Validates current_network not nil
#   * Validates dialog not cancelled
#   * begin/rescue/ensure with timestamped logging
# ---------------------------------------------------------------------------

def log(msg); puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] #{msg}"; end

begin
  exportloc = WSApplication.file_dialog(false, 'isfc', 'Collection Network Snapshot File', 'snapshot', false, false)
  if exportloc.nil?
    WSApplication.message_box('Export location required', 'OK', '!', nil)
    raise 'Export location not provided.'
  end

  nw = WSApplication.current_network
  raise 'No current network is open.' if nw.nil?

  export_tables = %w[cams_cctv_survey cams_manhole_survey]
  exp_options = {
    'SelectedOnly'      => true,
    'IncludeImageFiles' => true,
    'Tables'            => export_tables
  }

  log "Exporting selected rows to #{exportloc}..."
  nw.snapshot_export_ex(exportloc, exp_options)
  log 'Snapshot export complete.'
rescue StandardError => e
  log "Aborted: #{e.message}"
ensure
  log 'fix_UI-snapshot_export_ex.rb finished.'
end
