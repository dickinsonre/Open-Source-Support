# frozen_string_literal: true
# ============================================================================
# fix_SWMM5_Import_Exchange_Annotated.rb
# ----------------------------------------------------------------------------
# Purpose : Hardened wrapper around SWMM5_Import_Exchange_Annotated.rb, the
#           heavily commented "novice-friendly" Exchange worker that imports
#           one or more SWMM5 .inp files into ICM SWMM networks, with empty
#           label-list cleanup and post-import logging.
# Inputs  : ENV['ICM_IMPORT_CONFIG'] (YAML config written by the matching UI
#           script). Config supplies file paths, options, and log folder.
# Outputs : ICM SWMM network model group(s); annotated log files.
# Type    : Exchange (EX) script - headless via ICMExchange.exe.
# Hardening notes:
#   * frozen_string_literal pragma.
#   * begin/rescue/ensure wraps Kernel#load of the original.
#   * Pre-flight: original-script presence + config-file sanity check.
#   * Timestamped wrapper progress on stderr to aid debugging.
#   * Behavior of the original (including its annotated phases) preserved.
# ============================================================================

require 'time'

ORIGINAL_SCRIPT = File.join(__dir__, 'SWMM5_Import_Exchange_Annotated.rb').freeze

def fix_log(message)
  warn "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] [fix_wrapper] #{message}"
rescue StandardError
end

begin
  fix_log "Starting hardened wrapper for #{File.basename(ORIGINAL_SCRIPT)}"

  unless File.exist?(ORIGINAL_SCRIPT)
    raise "Original script not found: #{ORIGINAL_SCRIPT}"
  end

  cfg = ENV['ICM_IMPORT_CONFIG']
  if cfg && !cfg.empty? && !File.exist?(cfg)
    fix_log "WARNING: ICM_IMPORT_CONFIG points to a missing file: #{cfg}"
  end

  load ORIGINAL_SCRIPT
  fix_log 'Hardened wrapper completed.'
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
