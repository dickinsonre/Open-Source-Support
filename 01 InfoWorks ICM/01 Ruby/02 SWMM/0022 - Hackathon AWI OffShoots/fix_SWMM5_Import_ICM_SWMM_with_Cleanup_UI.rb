# frozen_string_literal: true
# ============================================================================
# fix_SWMM5_Import_ICM_SWMM_with_Cleanup_UI.rb
# ----------------------------------------------------------------------------
# Purpose : Hardened wrapper around
#           SWMM5_Import_ICM_SWMM_with_Cleanup_UI.rb (Version 2). UI script
#           that prompts for SWMM5 .inp file/directory, mode (Single, Batch,
#           Recursive), and options; writes YAML config; runs the matching
#           Exchange worker via ICMExchange.exe; reports summary statistics
#           via a written summary file.
# Inputs  : Interactive WSApplication prompts and file dialogs.
# Outputs : YAML config in "ICM Import Log Files/", launches Exchange worker,
#           displays summary dialog.
# Type    : UI script - runs inside InfoWorks ICM application.
# Hardening notes:
#   * frozen_string_literal pragma.
#   * begin/rescue/ensure around Kernel#load of the original.
#   * Verifies WSApplication availability and reports clean errors.
#   * Catches Interrupt for graceful cancel handling.
#   * Behavior of all underlying UI dialogs preserved.
# ============================================================================

require 'time'

ORIGINAL_SCRIPT = File.join(__dir__, 'SWMM5_Import_ICM_SWMM_with_Cleanup_UI.rb').freeze

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
