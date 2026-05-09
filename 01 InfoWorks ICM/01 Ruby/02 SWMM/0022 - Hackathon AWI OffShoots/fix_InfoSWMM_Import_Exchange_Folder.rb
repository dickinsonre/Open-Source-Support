# frozen_string_literal: true
# ============================================================================
# fix_InfoSWMM_Import_Exchange_Folder.rb
# ----------------------------------------------------------------------------
# Purpose : Hardened wrapper around InfoSWMM_Import_Exchange_Folder.rb.
#           Loads the original Exchange script which performs multi-scenario
#           InfoSWMM/H2OMapSWMM imports with deduplication, scenario merging,
#           label-list cleanup, and SWMM run setup.
# Inputs  : ENV['ICM_IMPORT_CONFIG'] -> path to YAML config produced by the
#           companion UI script. Config contains file_path, scenarios,
#           merge_scenarios, cleanup_empty_label_lists, copy_swmm_runs.
# Outputs : New ICM model groups (one per scenario plus a "Merged Scenarios"
#           group), SWMM runs (when enabled), and timestamped log files in
#           "<model_dir>/ICM Import Log Files/".
# Type    : Exchange (EX) script - runs headless via ICMExchange.exe.
# Hardening notes:
#   * frozen_string_literal pragma added.
#   * Outer begin/rescue/ensure guards the original script and surfaces
#     unexpected failures to stderr so the launcher captures them.
#   * Pre-flight checks: original script presence and ENV config sanity.
#   * Timestamped progress logging at start/finish of the wrapper run.
#   * Behavior of the underlying logic is preserved unchanged via Kernel#load.
# ============================================================================

require 'time'

ORIGINAL_SCRIPT = File.join(__dir__, 'InfoSWMM_Import_Exchange_Folder.rb').freeze

def fix_log(message)
  warn "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] [fix_wrapper] #{message}"
rescue StandardError
  # Logging must never break the wrapper.
end

begin
  fix_log "Starting hardened wrapper for #{File.basename(ORIGINAL_SCRIPT)}"

  unless File.exist?(ORIGINAL_SCRIPT)
    raise "Original script not found: #{ORIGINAL_SCRIPT}"
  end

  cfg = ENV['ICM_IMPORT_CONFIG']
  if cfg.nil? || cfg.empty?
    fix_log 'NOTE: ICM_IMPORT_CONFIG not set; original script will attempt to discover a config file.'
  elsif !File.exist?(cfg)
    fix_log "WARNING: ICM_IMPORT_CONFIG points to a missing file: #{cfg}"
  else
    fix_log "Config file: #{cfg}"
  end

  # Delegate to the original script. Behavior is preserved exactly.
  load ORIGINAL_SCRIPT

  fix_log 'Hardened wrapper completed.'
rescue SystemExit => e
  # The original script may call exit() with status codes - propagate.
  fix_log "Original script exited with status #{e.status}."
  raise
rescue StandardError => e
  fix_log "ERROR: #{e.class}: #{e.message}"
  fix_log "Backtrace (top 10):\n#{Array(e.backtrace).first(10).join("\n")}"
  raise
ensure
  fix_log 'Wrapper teardown.'
end
