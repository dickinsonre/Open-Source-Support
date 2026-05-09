# frozen_string_literal: true
# ============================================================================
# fix_InfoSWMM_Import_UI_Folder.rb
# ----------------------------------------------------------------------------
# Purpose : Hardened wrapper around InfoSWMM_Import_UI_Folder.rb. The original
#           is the user-facing UI script that prompts for an InfoSWMM .mxd /
#           H2OMapSWMM .hsm file, collects scenario list and options, writes a
#           YAML config, then launches the Exchange worker via ICMExchange.exe.
# Inputs  : Interactive WSApplication dialogs (file path, scenario string,
#           merge / cleanup / copy_swmm_runs flags).
# Outputs : YAML config in "<model_dir>/ICM Import Log Files/", launches
#           Exchange script, displays summary message boxes.
# Type    : UI script - runs inside the ICM application (must have a desktop
#           session and a loaded master database).
# Hardening notes:
#   * frozen_string_literal pragma.
#   * begin/rescue/ensure surrounds the load of the original.
#   * Detects WSApplication availability and reports a clear error if missing.
#   * Surfaces Interrupt (user-cancel) cleanly without scary stack traces.
#   * Behavior of underlying UI and prompts is preserved unchanged.
# ============================================================================

require 'time'

ORIGINAL_SCRIPT = File.join(__dir__, 'InfoSWMM_Import_UI_Folder.rb').freeze

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
      # ignore secondary failures
    end
  end
  raise
ensure
  fix_log 'Wrapper teardown.'
end
