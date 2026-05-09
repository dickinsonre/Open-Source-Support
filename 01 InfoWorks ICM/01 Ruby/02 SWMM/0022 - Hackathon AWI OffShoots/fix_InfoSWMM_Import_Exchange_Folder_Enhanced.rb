# frozen_string_literal: true
# ============================================================================
# fix_InfoSWMM_Import_Exchange_Folder_Enhanced.rb
# ----------------------------------------------------------------------------
# Purpose : Hardened wrapper around InfoSWMM_Import_Exchange_Folder_Enhanced.rb,
#           the enhanced Exchange script that supports both InfoSWMM (.mxd /
#           .ISDB) and H2OMapSWMM (.hsm / .HSDB) sources and emits richer DBF
#           statistics during multi-scenario import.
# Inputs  : ENV['ICM_IMPORT_CONFIG'] -> YAML config from the companion UI
#           script (file_path, scenarios, merge_scenarios, cleanup flag,
#           copy_swmm_runs flag).
# Outputs : Per-scenario model groups, optional merged-scenario model group,
#           SWMM runs, and structured logs in "ICM Import Log Files/".
# Type    : Exchange (EX) script - runs headless via ICMExchange.exe.
# Hardening notes:
#   * frozen_string_literal pragma added at top.
#   * begin/rescue/ensure wraps the entire Kernel#load delegation.
#   * Validates the original script exists and the config path (when set).
#   * Timestamped wrapper-level progress lines on stderr for diagnostics.
#   * Underlying logic and field-level statistics are preserved verbatim.
# ============================================================================

require 'time'

ORIGINAL_SCRIPT = File.join(__dir__, 'InfoSWMM_Import_Exchange_Folder_Enhanced.rb').freeze

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
