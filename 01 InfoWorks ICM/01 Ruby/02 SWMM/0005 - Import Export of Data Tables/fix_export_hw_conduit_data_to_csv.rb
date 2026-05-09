# frozen_string_literal: true
# ---------------------------------------------------------------------------
# fix_export_hw_conduit_data_to_csv.rb
#
# Purpose : Hardened wrapper around export_hw_conduit_data_to_csv.rb.
#           Validates environment and delegates to the original via load.
# Inputs  : Active current_network with hw_conduit rows + selection.
# Outputs : CSV plus optional stats table.
# Type    : UI script.
# Hardening:
#   * frozen_string_literal pragma
#   * WSApplication and current_network checks
#   * begin/rescue/ensure with timestamped logging
# ---------------------------------------------------------------------------

ORIGINAL = 'export_hw_conduit_data_to_csv.rb'

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
  log 'fix_export_hw_conduit_data_to_csv.rb finished.'
end
