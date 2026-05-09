# frozen_string_literal: true
# ---------------------------------------------------------------------------
# fix_hw_parameters.rb
#
# Purpose : Reference data file enumerating every InfoWorks (hw_*) table and
#           its fields.  Consumed by all_for_one_and_one_for_all.rb to drive
#           the dynamic export prompts.  This wrapper documents the original
#           and provides a defensive loader: it confirms the file exists and
#           is readable before any caller relies on it.
# Inputs  : None at load time; consumed by other scripts.
# Outputs : Console message indicating availability of the original.
# Type    : Reference / library file (loaded at runtime by other scripts).
# Hardening:
#   * frozen_string_literal pragma
#   * Validates the original .rb exists and is readable
#   * begin/rescue/ensure with timestamped logging
# ---------------------------------------------------------------------------

ORIGINAL = 'hw_parameters.rb'

def log(msg); puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] #{msg}"; end

begin
  here = File.dirname(File.expand_path(__FILE__))
  original_path = File.join(here, ORIGINAL)
  raise "Original parameters file not found: #{original_path}" unless File.exist?(original_path)
  raise "Original parameters file not readable: #{original_path}" unless File.readable?(original_path)
  size = File.size(original_path)
  log "#{ORIGINAL} present at #{original_path} (#{size} bytes)."
  log 'fix_hw_parameters.rb is a defensive reference shim - the original is the data file consumed by other scripts.'
rescue StandardError => e
  log "Aborted: #{e.message}"
ensure
  log 'fix_hw_parameters.rb finished.'
end
