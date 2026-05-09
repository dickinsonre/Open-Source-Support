# frozen_string_literal: true
# ---------------------------------------------------------------------------
# fix_all_for_one_and_one_for_all.rb
#
# Purpose : Hardened wrapper around all_for_one_and_one_for_all.rb - the
#           generic SWMM/InfoWorks table export driver with prompts and
#           dynamic field selection.  Pre-validates the environment then
#           delegates to the original implementation via Kernel#load.
# Inputs  : Active current_network; original script colocated.
# Outputs : Whatever the original produces (CSV files in user folder).
# Type    : UI script.
# Hardening:
#   * frozen_string_literal pragma
#   * Pre-checks WSApplication and current_network before running
#   * Verifies that the original .rb exists alongside this fix
#   * begin/rescue/ensure with timestamped logging
# ---------------------------------------------------------------------------

ORIGINAL = 'all_for_one_and_one_for_all.rb'

def log(msg); puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] #{msg}"; end

begin
  raise 'WSApplication is not available - run inside InfoWorks ICM.' unless defined?(WSApplication)
  cn = WSApplication.current_network
  raise 'No current network is open.' if cn.nil?

  here = File.dirname(File.expand_path(__FILE__))
  original_path = File.join(here, ORIGINAL)
  raise "Original script not found: #{original_path}" unless File.exist?(original_path)

  log "Delegating to #{ORIGINAL}..."
  load original_path
  log 'Delegated script returned.'
rescue StandardError => e
  log "Aborted: #{e.message}"
ensure
  log 'fix_all_for_one_and_one_for_all.rb finished.'
end
