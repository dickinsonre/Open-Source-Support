# frozen_string_literal: true
# ============================================================================
# fix_what_network_am_I_using.rb
# ----------------------------------------------------------------------------
# Purpose : Hardened wrapper around what_network_am_I_using.rb. Original
#           inspects the current network's table_names looking for an "hw_"
#           or "sw_" prefix to declare whether the loaded network is an
#           InfoWorks or SWMM network.
# Inputs  : current_network (HW or SW).
# Outputs : Message box stating the network type.
# Type    : UI script - runs inside InfoWorks ICM.
# Hardening notes:
#   * frozen_string_literal pragma.
#   * begin/rescue/ensure outer guard.
#   * Reports a clear message when no current network is loaded rather than
#     letting the original silently print a default string.
#   * Catches Interrupt; propagates SystemExit.
#   * Behavior preserved verbatim when the network is loaded.
# ============================================================================

require 'time'

ORIGINAL_SCRIPT = File.join(__dir__, 'what_network_am_I_using.rb').freeze

def fix_log(msg)
  puts "[#{Time.now.strftime('%H:%M:%S')}] [fix_wrapper] #{msg}"
rescue StandardError
end

begin
  fix_log "Starting hardened wrapper for #{File.basename(ORIGINAL_SCRIPT)}"

  raise "Original script not found: #{ORIGINAL_SCRIPT}" unless File.exist?(ORIGINAL_SCRIPT)
  raise 'WSApplication not available - run inside InfoWorks ICM.' unless defined?(WSApplication)

  net = WSApplication.current_network rescue nil
  if net.nil?
    fix_log 'NOTE: No current_network loaded; original will report "No network is currently open."'
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
  raise
ensure
  fix_log 'Wrapper teardown.'
end
