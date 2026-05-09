# frozen_string_literal: true
# ============================================================================
# fix_SWMM5_Import_ICM_InfoWorks_with_Cleanup_UI.rb
# ----------------------------------------------------------------------------
# Purpose : Hardened wrapper around
#           SWMM5_Import_ICM_InfoWorks_with_Cleanup_UI.rb (Version 3.1). UI
#           front-end that prompts the user for SWMM5 .inp source(s),
#           options, and target settings, writes a YAML config, then launches
#           the matching Exchange worker via ICMExchange.exe.
# Inputs  : Interactive WSApplication.prompt / file_dialog calls.
# Outputs : YAML config under "ICM Import Log Files/", launches Exchange
#           worker, presents summary dialog and statistics.
# Type    : UI script - runs inside InfoWorks ICM application.
# Hardening notes:
#   * frozen_string_literal pragma.
#   * begin/rescue/ensure surrounds the load of the original.
#   * Verifies WSApplication is available; reports a clean error otherwise.
#   * Catches Interrupt for graceful user-cancel handling.
#   * Behavior of underlying prompts and statistics formatting preserved.
# ============================================================================

require 'time'

ORIGINAL_SCRIPT = File.join(__dir__, 'SWMM5_Import_ICM_InfoWorks_with_Cleanup_UI.rb').freeze

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
