# frozen_string_literal: true
# ============================================================================
# fix_current_background_node_compare.rb
# ----------------------------------------------------------------------------
# Purpose : Hardened wrapper around current_background_node_compare.rb.
#           Original compares node parameters (X, Y, ground_level, flooding
#           discharge coeff, chamber_floor vs invert_elevation, "all common")
#           between current_network's hw_node and background_network's
#           sw_node, reporting per-parameter mean / max / min.
# Inputs  : current_network (HW), background_network (SW), prompt result.
# Outputs : Console statistics report.
# Type    : UI script - runs inside InfoWorks ICM.
# Hardening notes:
#   * frozen_string_literal pragma.
#   * begin/rescue/ensure outer guard.
#   * Validates BOTH current_network and background_network are loaded.
#   * Catches Interrupt; propagates SystemExit.
#   * Behavior preserved verbatim.
# ============================================================================

require 'time'

ORIGINAL_SCRIPT = File.join(__dir__, 'current_background_node_compare.rb').freeze

def fix_log(msg)
  puts "[#{Time.now.strftime('%H:%M:%S')}] [fix_wrapper] #{msg}"
rescue StandardError
end

begin
  fix_log "Starting hardened wrapper for #{File.basename(ORIGINAL_SCRIPT)}"

  raise "Original script not found: #{ORIGINAL_SCRIPT}" unless File.exist?(ORIGINAL_SCRIPT)
  raise 'WSApplication not available - run inside InfoWorks ICM.' unless defined?(WSApplication)

  cn = WSApplication.current_network rescue nil
  bn = WSApplication.background_network rescue nil
  raise 'No current_network loaded.' if cn.nil?
  raise 'No background_network loaded.' if bn.nil?

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
