# frozen_string_literal: true
# ============================================================================
# fix_master_all_1.rb
# ----------------------------------------------------------------------------
# Purpose : Hardened wrapper around master_all_1.rb. Original concatenates
#           multiple legacy SWMM / InfoWorks pipe-length statistics scripts
#           that scan sw_conduit / hw_conduit collections, compute thresholds
#           and medians, and select short links.
# Inputs  : current_network (HW or SW depending on phase).
# Outputs : Console statistics tables; selection state changes on network.
# Type    : UI script - runs inside InfoWorks ICM.
# Hardening notes:
#   * frozen_string_literal pragma.
#   * begin/rescue/ensure outer guard.
#   * Validates current_network is loaded.
#   * Catches Interrupt; propagates SystemExit.
#   * Behavior preserved verbatim.
# ============================================================================

require 'time'

ORIGINAL_SCRIPT = File.join(__dir__, 'master_all_1.rb').freeze

def fix_log(msg)
  puts "[#{Time.now.strftime('%H:%M:%S')}] [fix_wrapper] #{msg}"
rescue StandardError
end

begin
  fix_log "Starting hardened wrapper for #{File.basename(ORIGINAL_SCRIPT)}"

  raise "Original script not found: #{ORIGINAL_SCRIPT}" unless File.exist?(ORIGINAL_SCRIPT)
  raise 'WSApplication not available - run inside InfoWorks ICM.' unless defined?(WSApplication)

  net = WSApplication.current_network rescue nil
  raise 'No current_network loaded.' if net.nil?

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
