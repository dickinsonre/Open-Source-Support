# frozen_string_literal: true
# ---------------------------------------------------------------------------
# fix_hw_sw_all_table_reader.rb
#
# Purpose : Hardened wrapper around hw_sw_all_table_reader.rb - the combined
#           InfoWorks/SWMM driver that auto-detects the network type, loads
#           the matching parameters file, and runs interactive table exports.
# Inputs  : Active current_network; hw_parameters.rb / sw_parameters.rb in
#           the same folder.
# Outputs : Whatever the original produces (CSV files in user folder).
# Type    : UI script.
# Hardening:
#   * frozen_string_literal pragma
#   * Pre-checks WSApplication, current_network, and parameter files
#   * begin/rescue/ensure with timestamped logging
# ---------------------------------------------------------------------------

ORIGINAL = 'hw_sw_all_table_reader.rb'

def log(msg); puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] #{msg}"; end

begin
  raise 'WSApplication is not available - run inside InfoWorks ICM.' unless defined?(WSApplication)
  cn = WSApplication.current_network
  raise 'No current network is open.' if cn.nil?

  here = File.dirname(File.expand_path(__FILE__))
  original_path = File.join(here, ORIGINAL)
  raise "Original script not found: #{original_path}" unless File.exist?(original_path)

  hwp = File.join(here, 'hw_parameters.rb')
  swp = File.join(here, 'sw_parameters.rb')
  log "hw_parameters.rb #{File.exist?(hwp) ? 'present' : 'MISSING'}"
  log "sw_parameters.rb #{File.exist?(swp) ? 'present' : 'MISSING'}"

  log "Delegating to #{ORIGINAL}..."
  load original_path
  log 'Delegated script returned.'
rescue StandardError => e
  log "Aborted: #{e.message}"
ensure
  log 'fix_hw_sw_all_table_reader.rb finished.'
end
