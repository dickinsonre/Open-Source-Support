# frozen_string_literal: true
# ============================================================================
# fix_test_prompt_limit.rb
# ----------------------------------------------------------------------------
# Purpose : Hardened wrapper around test_prompt_limit.rb. Original probes
#           the maximum number of rows that WSApplication.prompt can render
#           by stepping from 10 to 250 boolean rows and watching for failure
#           or cancel.
# Inputs  : Repeated WSApplication.prompt dialogs.
# Outputs : Console progress messages indicating success / failure rows.
# Type    : UI script - runs inside InfoWorks ICM.
# Hardening notes:
#   * frozen_string_literal pragma.
#   * begin/rescue/ensure outer guard.
#   * Verifies WSApplication is available.
#   * Catches Interrupt for graceful cancel; propagates SystemExit.
#   * Behavior preserved verbatim.
# ============================================================================

require 'time'

ORIGINAL_SCRIPT = File.join(__dir__, 'test_prompt_limit.rb').freeze

def fix_log(msg)
  puts "[#{Time.now.strftime('%H:%M:%S')}] [fix_wrapper] #{msg}"
rescue StandardError
end

begin
  fix_log "Starting hardened wrapper for #{File.basename(ORIGINAL_SCRIPT)}"

  raise "Original script not found: #{ORIGINAL_SCRIPT}" unless File.exist?(ORIGINAL_SCRIPT)
  raise 'WSApplication not available - run inside InfoWorks ICM.' unless defined?(WSApplication)

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
  raise
ensure
  fix_log 'Wrapper teardown.'
end
