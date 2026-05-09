# frozen_string_literal: true
# ============================================================================
# fix_SWMM5_Import_UI_Annotated.rb
# ----------------------------------------------------------------------------
# Purpose : Hardened wrapper around SWMM5_Import_UI_Annotated.rb, the
#           heavily commented "novice-friendly" UI script. The original gets
#           settings from the user, builds a list of .inp files, writes the
#           YAML config, and dispatches the annotated Exchange worker.
# Inputs  : Interactive WSApplication prompts/dialogs.
# Outputs : YAML config and run logs in "ICM Import Log Files/", message
#           boxes summarizing results.
# Type    : UI script - runs inside InfoWorks ICM application.
# Hardening notes:
#   * frozen_string_literal pragma.
#   * begin/rescue/ensure surrounds the Kernel#load of the original.
#   * Validates WSApplication availability before invocation.
#   * Captures Interrupt cleanly when the user cancels.
#   * Behavior and copious annotation-style logging are preserved.
# ============================================================================

require 'time'

ORIGINAL_SCRIPT = File.join(__dir__, 'SWMM5_Import_UI_Annotated.rb').freeze

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
