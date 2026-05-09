# frozen_string_literal: true
# ---------------------------------------------------------------------------
# fix_ex;port_hw_weir_to_csv.rb
#
# Purpose : Hardened wrapper around ex;port_hw_weir_to_csv.rb (note literal
#           semicolon in name).  Delegates to original after sanity checks.
# Inputs  : Active current_network with hw_weir rows + selection.
# Outputs : CSV file plus optional stats table.
# Type    : UI script.
# Hardening:
#   * frozen_string_literal pragma
#   * WSApplication / current_network pre-validation
#   * Verifies original .rb exists
#   * begin/rescue/ensure with timestamped logging
# ---------------------------------------------------------------------------

ORIGINAL = 'ex;port_hw_weir_to_csv.rb'

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
  log 'fix_ex;port_hw_weir_to_csv.rb finished.'
end
