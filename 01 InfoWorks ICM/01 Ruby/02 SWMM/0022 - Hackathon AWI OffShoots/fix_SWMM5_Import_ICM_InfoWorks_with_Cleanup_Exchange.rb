# frozen_string_literal: true
# ============================================================================
# fix_SWMM5_Import_ICM_InfoWorks_with_Cleanup_Exchange.rb
# ----------------------------------------------------------------------------
# Purpose : Hardened wrapper around
#           SWMM5_Import_ICM_InfoWorks_with_Cleanup_Exchange.rb (Version 3,
#           refactored). Performs SWMM5 .inp imports into ICM SWMM Networks,
#           cleans empty sw_label artifacts, validates connectivity, and
#           reports performance timing using Ruby Logger.
# Inputs  : ENV['ICM_IMPORT_CONFIG'] (YAML config) defining single-file or
#           batch (recursive optional) input set, cleanup flag, and target
#           model group naming policy.
# Outputs : ICM SWMM model groups, structured Logger files, summary stats
#           file consumed by the UI for accurate post-run reporting.
# Type    : Exchange (EX) script - headless via ICMExchange.exe.
# Hardening notes:
#   * frozen_string_literal pragma.
#   * Outer begin/rescue/ensure surrounds the original.
#   * Pre-flight checks for original script and config file existence.
#   * Wrapper progress logged with timestamps via stderr.
#   * The original's structured logging and validation logic is preserved.
# ============================================================================

require 'time'

ORIGINAL_SCRIPT = File.join(__dir__, 'SWMM5_Import_ICM_InfoWorks_with_Cleanup_Exchange.rb').freeze

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
