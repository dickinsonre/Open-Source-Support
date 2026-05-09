# frozen_string_literal: true
# ---------------------------------------------------------------------------
# fix_export_sw_conduit_data_to_csv .rb
#
# (Note the trailing space in the original filename is preserved in this
#  fix filename per the request.)
#
# Purpose : Hardened wrapper around 'export_sw_conduit_data_to_csv .rb'.
# Inputs  : Active current_network with sw_conduit rows + selection.
# Outputs : CSV file plus optional stats.
# Type    : UI script.
# Hardening: pragma, WSApplication/network validation, begin/rescue/ensure,
#            log helper.
# ---------------------------------------------------------------------------

ORIGINAL = 'export_sw_conduit_data_to_csv .rb' # NB trailing space

def log(msg); puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] #{msg}"; end

begin
  raise 'WSApplication is not available - run inside InfoWorks ICM.' unless defined?(WSApplication)
  cn = WSApplication.current_network
  raise 'No current network is open.' if cn.nil?

  here = File.dirname(File.expand_path(__FILE__))
  original_path = File.join(here, ORIGINAL)
  raise "Original script not found: #{original_path}" unless File.exist?(original_path)

  log "Delegating to '#{ORIGINAL}'..."
  load original_path
  log 'Delegated script returned.'
rescue StandardError => e
  log "Aborted: #{e.message}"
ensure
  log "fix_export_sw_conduit_data_to_csv .rb finished."
end
