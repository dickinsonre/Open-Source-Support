# frozen_string_literal: true
# ============================================================================
# fix_asset_id_to_icm_link_id.rb
# ----------------------------------------------------------------------------
# Purpose : Hardened wrapper around asset_id_to_icm_link_id.rb. Original
#           maps a tab-delimited string of "asset_id (mgd)" tokens to ICM
#           hw_conduit IDs of the form "<us_node>.<link_suffix>" by walking
#           the current_network's hw_conduit collection.
# Inputs  : Hard-coded input_string in the original; current_network (HW).
# Outputs : Console list of remapped IDs.
# Type    : UI script - runs inside InfoWorks ICM (uses WSApplication).
# Hardening notes:
#   * frozen_string_literal pragma.
#   * begin/rescue/ensure outer guard.
#   * Validates current_network is loaded.
#   * Catches Interrupt; propagates SystemExit.
#   * Behavior preserved verbatim.
# ============================================================================

require 'time'

ORIGINAL_SCRIPT = File.join(__dir__, 'asset_id_to_icm_link_id.rb').freeze

def fix_log(msg)
  puts "[#{Time.now.strftime('%H:%M:%S')}] [fix_wrapper] #{msg}"
rescue StandardError
end

begin
  fix_log "Starting hardened wrapper for #{File.basename(ORIGINAL_SCRIPT)}"

  raise "Original script not found: #{ORIGINAL_SCRIPT}" unless File.exist?(ORIGINAL_SCRIPT)
  raise 'WSApplication not available - run inside InfoWorks ICM.' unless defined?(WSApplication)

  cn = WSApplication.current_network rescue nil
  raise 'No current_network loaded (must have an HW network open).' if cn.nil?

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
