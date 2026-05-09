# frozen_string_literal: true
# ============================================================================
# fix_SWMM5_Import_ICM_SWMM_with_Cleanup_Exchange.rb
# ----------------------------------------------------------------------------
# Purpose : Hardened wrapper around
#           SWMM5_Import_ICM_SWMM_with_Cleanup_Exchange.rb (Version 2). The
#           Exchange worker that processes single-file or batch (recursive
#           optional) SWMM5 .inp imports into ICM SWMM Networks, removes
#           empty label-list artifacts, validates results, and writes a
#           summary file for the UI.
# Inputs  : ENV['ICM_IMPORT_CONFIG'] (YAML).
# Outputs : ICM SWMM model groups, log files, batch summary file.
# Type    : Exchange (EX) script - headless via ICMExchange.exe.
# Hardening notes:
#   * frozen_string_literal pragma.
#   * Outer begin/rescue/ensure around the original-script load.
#   * Pre-flight check that the original script exists and ENV config (when
#     present) points to a real file.
#   * Wrapper-level timestamped logs to stderr for cross-script tracing.
#   * Underlying batch/aggregate statistics behavior is preserved.
# ============================================================================

require 'time'

ORIGINAL_SCRIPT = File.join(__dir__, 'SWMM5_Import_ICM_SWMM_with_Cleanup_Exchange.rb').freeze

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
