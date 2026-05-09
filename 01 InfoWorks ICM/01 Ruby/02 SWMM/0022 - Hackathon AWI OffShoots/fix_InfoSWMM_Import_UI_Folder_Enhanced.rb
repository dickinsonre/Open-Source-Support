# frozen_string_literal: true
# ============================================================================
# fix_InfoSWMM_Import_UI_Folder_Enhanced.rb
# ----------------------------------------------------------------------------
# Purpose : Hardened wrapper around InfoSWMM_Import_UI_Folder_Enhanced.rb, the
#           UI front-end for the enhanced multi-scenario InfoSWMM /
#           H2OMapSWMM importer. Includes the bundled DBFReader class and
#           emits comprehensive data-field statistics before launching the
#           Exchange worker.
# Inputs  : Interactive WSApplication dialogs (file selection, scenario list,
#           import options).
# Outputs : YAML config plus DBF statistics report in "ICM Import Log Files/",
#           launches the Exchange script, surfaces summary dialogs.
# Type    : UI script - runs inside InfoWorks ICM.
# Hardening notes:
#   * frozen_string_literal pragma.
#   * begin/rescue/ensure surrounds the original script.
#   * Validates WSApplication availability before dispatching.
#   * Catches Interrupt to keep the cancel path quiet.
#   * Behavior of underlying UI flow and DBFReader logic preserved.
# ============================================================================

require 'time'

ORIGINAL_SCRIPT = File.join(__dir__, 'InfoSWMM_Import_UI_Folder_Enhanced.rb').freeze

def fix_log(message)
  puts "[#{Time.now.strftime('%H:%M:%S')}] [fix_wrapper] #{message}"
rescue StandardError
end

begin
  fix_log "Starting hardened wrapper for #{File.basename(ORIGINAL_SCRIPT)}"

  unless File.exist?(ORIGINAL_SCRIPT)
    raise "Original script not found: #{ORIGINAL_SCRIPT}"
  end

  unless defined?(WSApplication)
    raise 'WSApplication not available - this UI script must run inside InfoWorks ICM.'
  end

  load ORIGINAL_SCRIPT
  fix_log 'Hardened wrapper completed.'
rescue Interrupt
  fix_log 'User cancelled (Interrupt).'
rescue SystemExit => e
  fix_log "Original script exited with status #{e.status}."
  raise
rescue StandardError => e
  fix_log "ERROR: #{e.class}: #{e.message}"
  fix_log "Backtrace (top 10):\n#{Array(e.backtrace).first(10).join("\n")}"
  if defined?(WSApplication) && WSApplication.respond_to?(:message_box)
    begin
      WSApplication.message_box("Import wrapper error:\n#{e.message}", 'OK', 'Error', false)
    rescue StandardError
    end
  end
  raise
ensure
  fix_log 'Wrapper teardown.'
end
