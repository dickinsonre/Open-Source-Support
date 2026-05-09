# frozen_string_literal: true
# ============================================================================
# fix_Compare InfoWorks to SWMM for Subcatchment and Node Inflows.rb
# ----------------------------------------------------------------------------
# Purpose : Hardened wrapper around "Compare InfoWorks to SWMM for
#           Subcatchment and Node Inflows.rb". Original cross-references HW
#           subcatchment population / trade_flow / base_flow /
#           additional_foul_flow against SW node base_flow / inflow_baseline
#           / additional_dwf, with optional copy-over flags.
# Inputs  : current_network (HW), background_network (SW), prompt selections.
# Outputs : Console comparison report; optional in-place updates wrapped
#           inside transactions in the original code.
# Type    : UI script - runs inside InfoWorks ICM.
# Hardening notes:
#   * frozen_string_literal pragma.
#   * begin/rescue/ensure outer guard with transaction_rollback on failure.
#   * Validates current_network AND background_network are loaded.
#   * Catches Interrupt; propagates SystemExit.
#   * Behavior of underlying comparison logic preserved verbatim.
# ============================================================================

require 'time'

ORIGINAL_SCRIPT = File.join(__dir__, 'Compare InfoWorks to SWMM for Subcatchment and Node Inflows.rb').freeze

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
  raise 'No current_network loaded (must have an HW network open).' if cn.nil?
  raise 'No background_network loaded (must have an SW network as background).' if bn.nil?

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
