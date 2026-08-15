# ============================================================================
# SWMM5 Import WITH CLEANUP - EXCHANGE SCRIPT (Version 3 - Refactored & Enhanced)
# ============================================================================
# 
# WHAT THIS SCRIPT DOES:
#   Processes SWMM5 .inp files via ICMExchange, importing them into ICM SWMM Networks.
#   
#   Phases: Import -> Cleanup (sw_label) -> Validation -> Reporting
#
# NEW IN VERSION 3:
#   - Refactored into functional components.
#   - Implemented cleanup of empty visualization labels (sw_label table).
#   - Enhanced validation logic (accurate connectivity checks).
#   - Added performance timing metrics.
#   - Uses Ruby Logger for structured log files.
#
# RUNS AUTOMATICALLY:
#   Launched by the UI script. Reads configuration via ENV['ICM_IMPORT_CONFIG'].
#
# ============================================================================

require 'yaml'
require 'logger'
require 'fileutils'
require 'set'

# ----------------------------------------------------------------------------
# Global State and Helpers
# ----------------------------------------------------------------------------

$script_logger = nil
$aggregate_stats = {
  files_processed: 0,
  files_successful: 0,
  files_failed: 0,
  total_nodes: 0,
  total_links: 0,
  total_subcatchments: 0,
  total_labels_cleaned: 0,
  total_import_time: 0.0,
  failed_files: [],
  # Imported but not committed because ICM validation reported errors
  files_invalid: 0,
  invalid_files: [],
  total_warnings: 0
}

# Dual logging: Console (simple) and File (structured)
def log(message, level = :info)
  # Output to console (ICMExchange stdout) for live streaming
  puts "[#{Time.now.strftime('%H:%M:%S')}] #{message}"
  # Output to log file
  $script_logger.send(level, message) if $script_logger
end

def time_it
  start_time = Time.now
  yield
  Time.now - start_time
end

# ----------------------------------------------------------------------------
# Initialization and Configuration
# ----------------------------------------------------------------------------
def initialize_script
  # Load configuration strictly from the environment variable
  config_file = ENV['ICM_IMPORT_CONFIG']
  unless config_file && File.exist?(config_file)
    puts "ERROR: Configuration file not found via ICM_IMPORT_CONFIG. Run the UI script first."
    exit 1
  end

  begin
    config = YAML.load_file(config_file)
  rescue => e
    puts "ERROR: Failed to parse configuration file: #{e.message}"
    exit 1
  end

  # Setup Logging
  log_dir = File.join(config['base_directory'], "ICM Import Log Files")
  FileUtils.mkdir_p(log_dir)

  log_filename = File.join(log_dir, "SWMM5_Batch_Import_#{Time.now.strftime('%Y%m%d_%H%M%S')}.log")
  
  $script_logger = Logger.new(log_filename)
  $script_logger.formatter = proc do |severity, datetime, progname, msg|
    "#{datetime.strftime('%Y-%m-%d %H:%M:%S')} [#{severity}] #{msg}\n"
  end

  # Open Database
  begin
    db = WSApplication.open
  rescue => e
    log "Error opening database: #{e.message}", :error
    exit 1
  end

  log "="*70
  log "SWMM5 Import to ICM (V3) - Exchange Script Initialized"
  log "="*70
  log "Database GUID: #{db.guid}"
  log "Files to process: #{config['file_configs'].length}"

  { config: config, db: db, log_dir: log_dir, log_filename: log_filename }
end

# ----------------------------------------------------------------------------
# Find or create a root-level Model Group to hold the imported networks.
# Networks cannot live directly at the database root, so all imports go here.
# ----------------------------------------------------------------------------
def find_or_create_model_group(db, group_name)
  db.root_model_objects.each do |o|
    return o if o.type == 'Model Group' && o.name == group_name
  end
  db.new_model_object('Model Group', group_name)
end

# ----------------------------------------------------------------------------
# Phase 1: Import File
# ----------------------------------------------------------------------------
def import_file(parent_group, file_path, network_name, log_dir)
  log "PHASE 1: Importing SWMM5 data"

  # A SWMM5 .inp is imported at the Model Group level with
  # import_all_sw_model_objects: it parses the file and CREATES the SWMM network
  # (plus any related objects) inside the group. You do NOT pre-create an empty
  # network and import into it - WSOpenNetwork has no #import_ex method.
  import_log_path = File.join(log_dir, "#{File.basename(file_path, '.inp')}_ImportLog_#{Time.now.strftime('%Y%m%d_%H%M%S')}.txt")

  imported_objects = nil
  import_time = time_it do
    imported_objects = parent_group.import_all_sw_model_objects(
        file_path.gsub('/', '\\'),        # SWMM5 .inp (Windows path)
        'inp',                            # format for SWMM5 INP files
        '',                               # scenario name (unused for INP)
        import_log_path.gsub('/', '\\')
    )
  end

  $aggregate_stats[:total_import_time] += import_time
  log "  Import duration: #{sprintf('%.2f', import_time)}s"

  # Handle failure - nothing imported
  if imported_objects.nil? || imported_objects.empty?
    log "  Import process reported failure. Check log: #{import_log_path}", :error
    if File.exist?(import_log_path)
        log "  --- Import Log Contents (First 100 lines) ---", :warn
        File.foreach(import_log_path).with_index do |line, i|
            log "    > #{line.strip}", :warn
            break if i >= 100
        end
        log "  ---------------------------------------------", :warn
    end
    raise "Import failed"
  end

  # Locate the SWMM network the import created (there should be exactly one).
  network = nil
  imported_objects.each { |o| network = o if o.type == 'SWMM network' }
  raise "Import produced no SWMM network object" if network.nil?

  log "  Imported #{imported_objects.length} object(s); network '#{network.name}' (ID: #{network.id})"

  # The import names the network after the .inp file - rename it to the name the
  # user configured. Non-fatal: keep the imported name if the rename is rejected.
  if network_name && !network_name.empty? && network.name != network_name
    begin
      network.name = network_name
      log "  Renamed network to '#{network_name}'"
    rescue => e
      log "  WARNING: Could not rename network to '#{network_name}': #{e.message}", :warn
    end
  end

  net = network.open

  log "  SUCCESS: Import completed."
  { net: net, network_obj: network }
end

# ----------------------------------------------------------------------------
# Phase 2: Cleanup (sw_label)
# ----------------------------------------------------------------------------
def cleanup_visualization_labels(net)
  log "PHASE 2: Cleaning up empty visualization labels (sw_label)"
  
  # In SWMM networks, visualization labels are stored in 'sw_label'.
  table_name = 'sw_label'

  # WSOpenNetwork has no #table_exists?, but it does expose #table_names.
  # Use that when available, and still guard the read itself.
  begin
    names = net.table_names
    if names && !names.map(&:to_s).include?(table_name)
      log "  No '#{table_name}' table in this network - nothing to clean."
      return 0
    end
  rescue
    # table_names unavailable - fall through and let the read decide
  end

  labels = begin
    net.row_objects(table_name)
  rescue => e
    log "  Skipping label cleanup (table '#{table_name}' unavailable: #{e.message})", :warn
    return 0
  end

  if labels.nil? || labels.empty?
    return 0
  end
  
  log "  Found #{labels.length} labels. Analyzing for empty content..."
  deleted_count = 0
  
  # Use transaction for safe deletion
  net.transaction_begin
  begin
    labels.each do |label|
      # Check the label text. Field access varies by ICM version, so try the
      # hash-style field first and fall back to the accessor.
      content = begin
        label['text'] || label['label']
      rescue
        begin
          label.label
        rescue
          nil
        end
      end

      if content.nil? || content.to_s.strip.empty?
        label.delete
        deleted_count += 1
      end
    end
    net.transaction_commit
    log "  SUCCESS: Deleted #{deleted_count} empty labels."
  rescue => e
    net.transaction_rollback
    log "  ERROR during label cleanup: #{e.message}. Transaction rolled back.", :error
    return 0
  end
  
  deleted_count
end

# ----------------------------------------------------------------------------
# Phase 3: Validation and Statistics
# ----------------------------------------------------------------------------
def validate_and_report(net)
  log "PHASE 3: Validation and Statistics"
  stats = { nodes: 0, links: 0, subcatchments: 0 }
  warnings = []

  begin
    nodes = net.row_objects('_nodes')
    links = net.row_objects('_links')
    subcatchments = net.row_objects('_subcatchments')

    stats[:nodes] = nodes.length
    stats[:links] = links.length
    stats[:subcatchments] = subcatchments.length

    log "  Statistics: Nodes=#{stats[:nodes]}, Links=#{stats[:links]}, Subs=#{stats[:subcatchments]}"

    # Check 1: Empty network
    if stats[:nodes] == 0 && stats[:links] == 0
      warnings << "Network is empty"
    end

    # Check 2: Disconnected subcatchments
    disconnected_subs = 0
    subcatchments.each do |sub|
      # Check both node_id and subcatchment_id for connection in SWMM networks
      if (sub.node_id.nil? || sub.node_id.empty?) && (sub.subcatchment_id.nil? || sub.subcatchment_id.empty?)
          disconnected_subs += 1
      end
    end
    if disconnected_subs > 0
      warnings << "#{disconnected_subs} subcatchment(s) have no outlet (node or subcatchment)"
    end

    # Check 3: Unconnected nodes (Islanding) - Comprehensive and Robust Check
    connected_nodes = Set.new
    
    # Nodes connected by links
    links.each do |link|
      connected_nodes.add(link.us_node_id) if link.us_node_id && !link.us_node_id.empty?
      connected_nodes.add(link.ds_node_id) if link.ds_node_id && !link.ds_node_id.empty?
    end
    
    # Nodes connected as subcatchment outlets
    subcatchments.each do |sub|
      # We only care if it connects to a node here (sub-to-sub connections don't count for node connectivity)
      connected_nodes.add(sub.node_id) if sub.node_id && !sub.node_id.empty?
    end

    all_node_ids = Set.new
    nodes.each { |node| all_node_ids.add(node.id) }

    # Calculate the difference
    unconnected_nodes = all_node_ids - connected_nodes
    if unconnected_nodes.any?
      examples = unconnected_nodes.to_a.take(5).join(', ')
      warnings << "#{unconnected_nodes.size} node(s) are unconnected (Islands). Examples: #{examples}"
    end

    if warnings.any?
      log "  Validation finished with #{warnings.length} warning(s):", :warn
      warnings.each { |w| log "    * #{w}", :warn }
    else
      log "  Validation passed with no warnings."
    end

  rescue => e
    log "  ERROR during validation/statistics analysis: #{e.message}", :error
  end
  
  stats
end

# ----------------------------------------------------------------------------
# Main Processing Loop
# ----------------------------------------------------------------------------
def main_process_loop(init_data)
  config = init_data[:config]
  db = init_data[:db]
  log_dir = init_data[:log_dir]
  file_configs = config['file_configs']

  log "\n" + "="*70
  log "BATCH PROCESSING STARTING"
  log "="*70

  # Networks must be created inside a Model Group, not at the database root.
  # Reuse (or create) a single root-level group to hold every imported network.
  import_group_name = config['import_group_name'] || 'SWMM5 Imports'
  import_group = find_or_create_model_group(db, import_group_name)
  log "Target Model Group: '#{import_group.name}' (ID: #{import_group.id})"

  file_configs.each_with_index do |file_config, index|
    file_basename = file_config['file_basename']
    file_path = file_config['file_path']
    network_name = file_config['network_name']

    log "\n" + "-"*70
    log "[#{index + 1}/#{file_configs.length}] Processing: #{file_basename}"
    log "-"*70

    $aggregate_stats[:files_processed] += 1
    network_obj = nil
    import_succeeded = false

    begin
      # Input Validation
      raise "File not found" unless File.exist?(file_path)

      # Phase 1: Import
      import_result = import_file(import_group, file_path, network_name, log_dir)
      net = import_result[:net]
      network_obj = import_result[:network_obj]
      import_succeeded = true

      # Phase 2: Cleanup (optional - never fail a good import over cosmetics)
      labels_cleaned = 0
      if config['cleanup_empty_label_lists']
        begin
          labels_cleaned = cleanup_visualization_labels(net)
        rescue => e
          log "  WARNING: Label cleanup skipped: #{e.message}", :warn
          labels_cleaned = 0
        end
      end

      # Phase 3: Validation (optional - reporting only, must not fail the import)
      import_stats = {}
      if config['validate_after_import']
        begin
          import_stats = validate_and_report(net)
        rescue => e
          log "  WARNING: Post-import validation skipped: #{e.message}", :warn
          import_stats = {}
        end
      end

      # Phase 4: ICM network validation (net.validate) - gates the commit.
      # Returns a collection exposing .error_count / .warning_count / .length,
      # with .message on each entry.
      icm_errors   = 0
      icm_warnings = 0
      validation_ran = false

      if config['run_icm_validation']
        begin
          scenarios = ['Base']
          log "PHASE 4: ICM validation (scenario: #{scenarios.join(', ')})"
          validations = net.validate(scenarios)

          icm_errors   = validations.error_count
          icm_warnings = validations.warning_count
          validation_ran = true

          log "  Validation: #{icm_errors} error(s), #{icm_warnings} warning(s)"

          # Record the messages so failures are diagnosable after the run.
          if validations.length > 0
            val_report = File.join(log_dir, "#{File.basename(file_path, '.inp')}_Validation.txt")
            File.open(val_report, 'w') do |f|
              f.puts "Validation for #{file_basename} (network: #{network_name})"
              f.puts "Errors: #{icm_errors}  Warnings: #{icm_warnings}"
              f.puts "-" * 60
              validations.each { |v| f.puts v.message }
            end
            log "  Validation messages written to: #{File.basename(val_report)}"

            validations.each_with_index do |v, i|
              log "    #{v.message}", (icm_errors > 0 ? :warn : :info)
              break if i >= 9   # keep the main log readable
            end
          end
        rescue => e
          log "  WARNING: ICM validation could not run: #{e.message}", :warn
          validation_ran = false
        end
      end

      # Finalize: Commit - only if validation did not report errors.
      if validation_ran && icm_errors > 0
        $aggregate_stats[:files_invalid] += 1
        $aggregate_stats[:invalid_files] << {
          file: file_basename, network: network_name, errors: icm_errors, warnings: icm_warnings
        }

        if config['commit_even_if_invalid']
          # WSOpenNetwork#commit_bypassing_validation exists precisely for this:
          # keep the data in version control even though ICM flags errors.
          begin
            net.commit_bypassing_validation(
              "Imported SWMM5: #{file_basename}. COMMITTED WITH #{icm_errors} VALIDATION ERROR(S)")
            log "COMMITTED DESPITE #{icm_errors} validation error(s): #{file_basename}", :warn
            $aggregate_stats[:total_nodes] += import_stats[:nodes] || 0
            $aggregate_stats[:total_links] += import_stats[:links] || 0
            $aggregate_stats[:total_subcatchments] += import_stats[:subcatchments] || 0
            $aggregate_stats[:total_labels_cleaned] += labels_cleaned
          rescue => e
            log "  Bypass commit failed: #{e.message}", :error
          end
        else
          log "SKIPPED COMMIT: #{file_basename} - #{icm_errors} validation error(s)", :warn
          # Leave the network in place (uncommitted) so it can be inspected/fixed.
        end
      else
        commit_message = "Imported SWMM5: #{file_basename}."
        commit_message += " (Cleaned #{labels_cleaned} empty labels)" if labels_cleaned > 0
        commit_message += " (#{icm_warnings} validation warning(s))" if icm_warnings > 0

        net.commit(commit_message)
        log "Network committed."

        $aggregate_stats[:files_successful] += 1
        $aggregate_stats[:total_nodes] += import_stats[:nodes] || 0
        $aggregate_stats[:total_links] += import_stats[:links] || 0
        $aggregate_stats[:total_subcatchments] += import_stats[:subcatchments] || 0
        $aggregate_stats[:total_labels_cleaned] += labels_cleaned
        $aggregate_stats[:total_warnings] += icm_warnings

        log "SUCCESS: #{file_basename}"
      end

      # Release the network handle. Also gives the database a clean close for
      # every import, rather than leaving handles open until the process exits.
      begin
        net.close
      rescue => e
        log "  (Could not close network handle: #{e.message})", :warn
      end

    rescue => e
      # Error Handling
      log "FAILURE: Failed to process #{file_basename}. Reason: #{e.message}", :error
      $script_logger.error("Backtrace:\n#{e.backtrace.join("\n")}") if $script_logger
      
      $aggregate_stats[:files_failed] += 1
      $aggregate_stats[:failed_files] << { file: file_basename, reason: e.message }

      # Only discard the network if the IMPORT itself failed. Once Phase 1 has
      # succeeded the data is good, and a later (optional) phase blowing up must
      # never delete a network the user just successfully imported.
      if network_obj && !import_succeeded
        begin
          # WSDatabase has no #find_model_object. Walk the database tree to confirm
          # the partially-created network still exists before attempting to delete
          # it (by name, as the ID may be unreliable if creation failed partially).
          exists = false
          queue = []
          db.root_model_objects.each { |o| queue << o }
          until queue.empty?
            obj = queue.shift
            if obj.type == 'SWMM network' && obj.name == network_name
              exists = true
              break
            end
            obj.children.each { |child| queue << child }
          end

          if exists
            log "Attempting to delete partially processed network '#{network_name}'..."
            network_obj.delete
            log "Successfully deleted network object."
          end
        rescue => cleanup_error
          log "Could not delete network object during cleanup: #{cleanup_error.message}", :error
        end
      end
    end
  end
end

# ----------------------------------------------------------------------------
# Summary Generation
# ----------------------------------------------------------------------------
def generate_summary(init_data, duration)
  log_dir = init_data[:log_dir]

  log "\n" + "="*70
  log "BATCH IMPORT SUMMARY"
  log "="*70
  log "Total duration: #{sprintf('%.2f', duration)}s"
  log "Files processed: #{$aggregate_stats[:files_processed]}"
  log "Successful: #{$aggregate_stats[:files_successful]}"
  log "Failed: #{$aggregate_stats[:files_failed]}"
  log "Imported but NOT committed (validation errors): #{$aggregate_stats[:files_invalid]}"

  if $aggregate_stats[:files_invalid] > 0
    log "\nNetworks left uncommitted (fix and commit manually):"
    $aggregate_stats[:invalid_files].each do |v|
      log "  * #{v[:network]} - #{v[:errors]} error(s), #{v[:warnings]} warning(s)  [#{v[:file]}]", :warn
    end
  end

  if $aggregate_stats[:files_successful] > 0
    log "\nAggregate Statistics:"
    log "  Nodes: #{$aggregate_stats[:total_nodes]}"
    log "  Links: #{$aggregate_stats[:total_links]}"
    log "  Subcatchments: #{$aggregate_stats[:total_subcatchments]}"
    log "  Empty Labels Cleaned: #{$aggregate_stats[:total_labels_cleaned]}"

    log "\nPerformance Metrics:"
    avg_import = $aggregate_stats[:total_import_time] / $aggregate_stats[:files_successful]
    log "  Total Import Time: #{sprintf('%.2f', $aggregate_stats[:total_import_time])}s (Avg: #{sprintf('%.2f', avg_import)}s)"
  end

  if $aggregate_stats[:failed_files].any?
    log "\nFailed Files:", :warn
    $aggregate_stats[:failed_files].each do |failed|
      log "  * #{failed[:file]}: #{failed[:reason]}", :warn
    end
  end

  # Write summary file for UI script
  summary_file = File.join(log_dir, "batch_summary.txt")
  begin
    File.open(summary_file, 'w') do |f|
        f.puts "BATCH_IMPORT_SUMMARY"
        f.puts "files_processed=#{$aggregate_stats[:files_processed]}"
        f.puts "files_successful=#{$aggregate_stats[:files_successful]}"
        f.puts "files_failed=#{$aggregate_stats[:files_failed]}"
        f.puts "total_nodes=#{$aggregate_stats[:total_nodes]}"
        f.puts "total_links=#{$aggregate_stats[:total_links]}"
        f.puts "total_subcatchments=#{$aggregate_stats[:total_subcatchments]}"
        f.puts "total_labels_cleaned=#{$aggregate_stats[:total_labels_cleaned]}"
        f.puts "files_invalid=#{$aggregate_stats[:files_invalid]}"
        f.puts "total_warnings=#{$aggregate_stats[:total_warnings]}"
        f.puts "total_duration=#{sprintf('%.2f', duration)}"
    end
  rescue => e
    log "ERROR: Failed to write summary file: #{e.message}", :error
  end
end

# ============================================================================
# Script Execution
# ============================================================================
start_time = Time.now
init_data = nil
begin
  init_data = initialize_script
  main_process_loop(init_data)
rescue => e
  log "A critical error occurred during execution: #{e.message}", :fatal
  log e.backtrace.join("\n"), :fatal
ensure
  duration = Time.now - start_time
  generate_summary(init_data, duration) if init_data
  $script_logger.close if $script_logger
end

# Exit with appropriate code
exit($aggregate_stats[:files_failed] > 0 ? 1 : 0)