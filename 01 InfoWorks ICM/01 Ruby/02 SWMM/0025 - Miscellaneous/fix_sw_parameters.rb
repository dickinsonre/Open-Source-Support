# frozen_string_literal: true
# ============================================================================
# fix_sw_parameters.rb
# ----------------------------------------------------------------------------
# Purpose : Hardened wrapper around sw_parameters.rb. Original is a
#           reference listing of all sw_options / sw_subcatchment field
#           names (with _flag fields), kept as a quick lookup. No
#           executable code in the original.
# Inputs  : None.
# Outputs : None (the original file is comments-only).
# Type    : Reference document (.rb extension) - does NOT require ICM.
# Hardening notes:
#   * frozen_string_literal pragma.
#   * begin/rescue/ensure outer guard.
#   * Catches Interrupt; propagates SystemExit.
#   * Behavior preserved verbatim.
# ============================================================================

require 'time'

ORIGINAL_SCRIPT = File.join(__dir__, 'sw_parameters.rb').freeze

def fix_log(msg)
  puts "[#{Time.now.strftime('%H:%M:%S')}] [fix_wrapper] #{msg}"
rescue StandardError
end

begin
  fix_log "Starting hardened wrapper for #{File.basename(ORIGINAL_SCRIPT)}"
  raise "Original script not found: #{ORIGINAL_SCRIPT}" unless File.exist?(ORIGINAL_SCRIPT)

  load ORIGINAL_SCRIPT
  fix_log 'Hardened wrapper completed (reference file - no runtime output expected).'
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
