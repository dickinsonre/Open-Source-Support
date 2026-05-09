# frozen_string_literal: true
# ============================================================================
# fix_sonnet_exchange_centroid_bn_cn_networks.rb
# ----------------------------------------------------------------------------
# Purpose : Hardened wrapper around sonnet_exchange_centroid_bn_cn_networks.rb.
#           Original cross-checks current vs background networks: compares
#           hw_node ground_level against sw_node, optionally copies fields,
#           lists unique objects, finds nearby objects within a radius, and
#           computes centroid / farthest-distance summaries.
# Inputs  : current_network (HW) and background_network (SW).
# Outputs : Console listings; optional in-place updates wrapped in a
#           transaction inside the original.
# Type    : UI script - runs inside InfoWorks ICM.
# Hardening notes:
#   * frozen_string_literal pragma.
#   * begin/rescue/ensure outer guard with transaction_rollback on failure.
#   * Validates BOTH current_network and background_network are loaded.
#   * Catches Interrupt; propagates SystemExit.
#   * Behavior preserved verbatim.
# ============================================================================

require 'time'

ORIGINAL_SCRIPT = File.join(__dir__, 'sonnet_exchange_centroid_bn_cn_networks.rb').freeze

def fix_log(msg)
  puts "[#{Time.now.strftime('%H:%M:%S')}] [fix_wrapper] #{msg}"
rescue StandardError
end

cn = nil
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
  begin
    cn&.transaction_rollback
    fix_log 'Attempted transaction_rollback on current_network.'
  rescue StandardError
  end
  raise
ensure
  fix_log 'Wrapper teardown.'
end
