# frozen_string_literal: true
# ============================================================================
# fix_Bill_James_Similarity_Index.rb
# ----------------------------------------------------------------------------
# Purpose : Hardened wrapper around Bill_James_Similarity_Index.rb. Original
#           defines a HydraulicNetworkComparison class that scores hydraulic
#           output similarity (means, RMSE, MAPE, NSE, KGE, etc.) using the
#           Bill James Similarity Index methodology, with weighted metrics.
# Inputs  : In-script demonstration arrays; no ICM dependencies.
# Outputs : Console scoring report.
# Type    : Standalone tutorial / demo script - does NOT require ICM.
# Hardening notes:
#   * frozen_string_literal pragma.
#   * begin/rescue/ensure outer guard.
#   * No network validation needed (script does not access WSApplication).
#   * Catches Interrupt; propagates SystemExit.
#   * Behavior preserved verbatim.
# ============================================================================

require 'time'

ORIGINAL_SCRIPT = File.join(__dir__, 'Bill_James_Similarity_Index.rb').freeze

def fix_log(msg)
  puts "[#{Time.now.strftime('%H:%M:%S')}] [fix_wrapper] #{msg}"
rescue StandardError
end

begin
  fix_log "Starting hardened wrapper for #{File.basename(ORIGINAL_SCRIPT)}"
  raise "Original script not found: #{ORIGINAL_SCRIPT}" unless File.exist?(ORIGINAL_SCRIPT)

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
