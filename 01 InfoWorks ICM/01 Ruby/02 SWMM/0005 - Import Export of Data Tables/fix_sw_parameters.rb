# frozen_string_literal: true
# ---------------------------------------------------------------------------
# fix_sw_parameters.rb
#
# Purpose : Reference data file enumerating every ICM SWMM (sw_*) table and
#           its fields.  Consumed by hw_sw_all_table_reader.rb /
#           all_for_one_and_one_for_all.rb to drive the dynamic export
#           prompts.  This shim verifies the original file is present and
#           readable.
# Inputs  : None at load time.
# Outputs : Console message confirming availability.
# Type    : Reference / library file.
# Hardening:
#   * frozen_string_literal pragma
#   * File existence and readability checks
#   * begin/rescue/ensure with timestamped logging
# ---------------------------------------------------------------------------

ORIGINAL = 'sw_parameters.rb'

def log(msg); puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] #{msg}"; end

begin
  here = File.dirname(File.expand_path(__FILE__))
  original_path = File.join(here, ORIGINAL)
  raise "Original parameters file not found: #{original_path}" unless File.exist?(original_path)
  raise "Original parameters file not readable: #{original_path}" unless File.readable?(original_path)
  size = File.size(original_path)
  log "#{ORIGINAL} present at #{original_path} (#{size} bytes)."
  log 'fix_sw_parameters.rb is a defensive reference shim - the original is the data file consumed by other scripts.'
rescue StandardError => e
  log "Aborted: #{e.message}"
ensure
  log 'fix_sw_parameters.rb finished.'
end
