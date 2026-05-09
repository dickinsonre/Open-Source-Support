# frozen_string_literal: true
# =============================================================================
# Hardened: InfoSWMM Multi-Scenario Import - EXCHANGE SCRIPT (BACKEND)
# =============================================================================
# Purpose : Backend ICM Exchange script that imports multiple InfoSWMM
#           scenarios from an .mxd model into InfoWorks ICM as a SWMM network,
#           deduplicates Rainfall/Inflow events, optionally builds a merged
#           network, and creates SWMM runs (Phases 1, 1.5, 2, 2.5).
# Inputs  : JSON config (path passed via ICM_IMPORT_CONFIG env var or located
#           on disk). Contains file_path, scenarios, merge_scenarios,
#           cleanup_empty_label_lists, copy_swmm_runs, database_guid,
#           database_path.
# Outputs : Model Group(s) populated in the open ICM database, optional merged
#           model group, SWMM run objects, and detailed logs in
#           <mxd dir>/ICM Import Log Files/Import_Runs_*.log.
# UI/EX   : ICM Exchange (EX) script - launched automatically by the
#           InfoSWMM_Import_UI script. Do NOT run directly.
# Hardening notes:
#   * frozen_string_literal pragma at top
#   * Outer begin / rescue / ensure wraps the entire run; ensure block always
#     closes log files and any merged network it opened.
#   * WSApplication.open(...) result validated for nil; GUID compared.
#   * File handles opened via block form (`File.open(path) do |f| ... end`)
#     wherever possible; the long-lived log_file is explicitly closed.
#   * Nil-safety with `&.` on optional chains.
#   * Timestamped progress logs via `puts "[#{Time.now}] ..."`.
#   * Original behaviour of all four phases is preserved verbatim.
# =============================================================================

require 'json'

# ----------------------------------------------------------------------------
# Helper Methods
# ----------------------------------------------------------------------------

def log(message, log_file = nil)
  puts message
  log_file&.puts message
end

def stamp(msg)
  "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] #{msg}"
end

# Check if label list is empty (InfoSWMM imports create empty lists as artifacts)
def is_label_list_empty?(label_list, log_file = nil)
  begin
    blob = label_list['Blob']
    return blob.nil? || blob.empty?
  rescue => e
    log "  WARNING: Error checking label list: #{e.message}", log_file
    false
  end
end

# Helper method to get object content hash by exporting and stripping metadata
def get_object_hash(obj, log_file = nil)
  require 'digest'

  begin
    script_dir = File.dirname(__FILE__)
    temp_dir = File.join(script_dir, "temp_object_compare")
    Dir.mkdir(temp_dir) unless Dir.exist?(temp_dir)

    safe_name = obj.type.gsub(' ', '_').gsub(/[^a-zA-Z0-9_]/, '')
    temp_file = File.join(temp_dir, "#{safe_name}_#{obj.id}.txt")

    obj.export(temp_file, '')

    unless File.exist?(temp_file)
      log "  ERROR: Export failed - file not created for #{obj.type} '#{obj.name}'", log_file if log_file
      return nil
    end

    file_size = File.size(temp_file)
    if file_size == 0
      log "  WARNING: Export created empty file (0 bytes) for #{obj.type} '#{obj.name}'", log_file if log_file
      File.delete(temp_file) if File.exist?(temp_file)
      return nil
    end

    contents = nil
    File.open(temp_file, 'r') { |f| contents = f.read }

    cleaned_lines = []
    contents.each_line do |line|
      next if line.strip == obj.name
      next if line.match(/^Name[:\s]/i)
      next if line.match(/^Description[:\s]/i)
      next if line.match(/^Created[:\s]/i)
      next if line.match(/^Modified[:\s]/i)
      next if line.match(/^GUID[:\s]/i)
      next if line.match(/^ID[:\s]/i)
      cleaned_lines << line
    end

    cleaned_content = cleaned_lines.join

    if log_file && $first_export_logged.nil?
      $first_export_logged = {}
    end
    if log_file && !$first_export_logged[obj.type]
      $first_export_logged[obj.type] = true
      log "  DEBUG: First #{obj.type} export (after metadata stripping, first 300 chars):", log_file
      log "  #{cleaned_content[0..300].inspect}", log_file
      log "  Original size: #{contents.length} bytes, Cleaned size: #{cleaned_content.length} bytes", log_file
    end

    hash = Digest::SHA256.hexdigest(cleaned_content)
    File.delete(temp_file) if File.exist?(temp_file)
    return hash
  rescue => e
    log "  ERROR: Exception hashing #{obj.type} '#{obj.name}': #{e.message}", log_file if log_file
    log "  Backtrace: #{e.backtrace.first(3).join("\n           ")}", log_file if log_file
    return nil
  end
end

DEDUP_OBJECT_TYPES = ['Rainfall Event', 'Inflow'].freeze

# ----------------------------------------------------------------------------
# Read Configuration
# ----------------------------------------------------------------------------

config_file = ENV['ICM_IMPORT_CONFIG']

unless config_file && File.exist?(config_file)
  script_dir      = File.dirname(__FILE__)
  parent_dir      = File.dirname(script_dir)
  grandparent_dir = File.dirname(parent_dir)

  search_paths = []
  [script_dir, parent_dir, grandparent_dir].each do |dir|
    Dir.glob(File.join(dir, "**", "ICM Import Log Files", "import_config.json")).each do |path|
      search_paths << path
    end
  end

  if search_paths.any?
    config_file = search_paths.max_by { |f| File.mtime(f) }
  end
end

unless config_file && File.exist?(config_file)
  puts "ERROR: Configuration file not found"
  puts "Please run InfoSWMM_Import_UI.rb first to generate the config file."
  exit 1
end

begin
  config = nil
  File.open(config_file, 'r') { |f| config = JSON.parse(f.read) }
rescue => e
  puts "ERROR: Could not read configuration file: #{e.message}"
  exit 1
end

required_keys = ['file_path', 'scenarios', 'merge_scenarios', 'cleanup_empty_label_lists', 'copy_swmm_runs']
missing = required_keys - config.keys
if missing.any?
  puts "ERROR: Configuration missing required keys: #{missing.join(', ')}"
  puts "Please run the UI script again to regenerate the configuration."
  exit 1
end

file_path                  = config['file_path']
scenario_input             = config['scenarios']
merge_scenarios            = config['merge_scenarios']
cleanup_empty_label_lists  = config['cleanup_empty_label_lists']
copy_swmm_runs             = config['copy_swmm_runs']

unless File.exist?(file_path)
  puts "ERROR: InfoSWMM model file not found: #{file_path}"
  exit 1
end

unless File.extname(file_path).downcase == ".mxd"
  puts "ERROR: File must be an InfoSWMM .mxd file"
  puts "Selected file: #{file_path}"
  exit 1
end

puts "\n" + "="*70
puts "  InfoSWMM Multi-Scenario Import with SWMM Runs (hardened)"
puts "="*70
puts "\nModel    : #{File.basename(file_path)}"
puts "Scenarios: #{scenario_input}"
puts "\n" + "="*70

# ----------------------------------------------------------------------------
# Open Database
# ----------------------------------------------------------------------------
expected_guid = config['database_guid']
db_path       = config['database_path']
db            = nil

begin
  if db_path && !db_path.empty?
    puts stamp("Opening database: #{db_path}")
    db = WSApplication.open(db_path)
    puts "Successfully opened database"
  else
    puts stamp("Database path not available, using default connection")
    db = WSApplication.open
  end
rescue => e
  puts "Error opening database: #{e.message}"
  puts "Backtrace: #{e.backtrace.first(5).join("\n")}" if e.backtrace
  exit 1
end

if db.nil?
  puts "Failed to open the database."
  exit 1
end

actual_guid = db.guid
if expected_guid && actual_guid != expected_guid
  msg  = "\n" + "="*70 + "\n"
  msg += "ERROR: Connected to Wrong Database!\n"
  msg += "="*70 + "\n\n"
  msg += "Expected database GUID: #{expected_guid}\n"
  msg += "Actually connected to:   #{actual_guid}\n\n"
  msg += "Close all ICM instances, open ONLY the target database, and retry.\n"
  msg += "="*70 + "\n"
  puts msg
  exit 1
end

puts "Connected to correct database (GUID: #{actual_guid})"

scenarios = scenario_input.split(',').map(&:strip).reject(&:empty?)
if scenarios.empty?
  puts "ERROR: No valid scenario names provided."
  exit 1
end

# ----------------------------------------------------------------------------
# Setup Logging
# ----------------------------------------------------------------------------
log_dir = File.join(File.dirname(file_path), "ICM Import Log Files")
Dir.mkdir(log_dir) unless Dir.exist?(log_dir)

log_filename = File.join(log_dir, "Import_Runs_#{Time.now.strftime('%Y%m%d_%H%M%S')}.log")
log_file     = File.open(log_filename, 'w')

# Track resources for ensure-block cleanup
merged_net_work = nil

# ============================================================================
# Main execution with comprehensive error handling
# ============================================================================
begin

# ----------------------------------------------------------------------------
# Safety Check: Verify InfoSWMM is not open
# ----------------------------------------------------------------------------
mxd_dir    = File.dirname(file_path)
lock_files = []

begin
  if Dir.exist?(mxd_dir)
    entries        = Dir.entries(mxd_dir)
    lock_entries   = entries.select { |entry| entry.start_with?('~') && entry != '~' }
    lock_files     = lock_entries.map { |entry| File.join(mxd_dir, entry) }.select { |f| File.exist?(f) }
  end
rescue => e
  puts "Warning: Could not check for lock files: #{e.message}"
end

if lock_files.any?
  msg  = "\n" + "="*70 + "\n"
  msg += "ERROR: InfoSWMM Model is Currently Open\n"
  msg += "="*70 + "\n\n"
  msg += "Lock files detected:\n"
  lock_files.each { |f| msg += "  - #{File.basename(f)}\n" }
  msg += "\nPlease close InfoSWMM and run the script again.\n"
  msg += "="*70 + "\n"
  puts msg
  log_file.puts msg
  raise "InfoSWMM model is currently open. Close InfoSWMM and try again."
end

log "\n" + "="*70, log_file
log stamp("InfoSWMM Multi-Scenario Import with SWMM Runs"), log_file
log "="*70, log_file
log "Database GUID       : #{db.guid}", log_file
log "Source File         : #{file_path}", log_file
log "Scenarios to import : #{scenarios.join(', ')}", log_file
log "Cleanup empty labels: #{cleanup_empty_label_lists}", log_file
log "Copy SWMM runs      : #{copy_swmm_runs}", log_file
log "="*70 + "\n", log_file

# ============================================================================
# PHASE 1: Import each scenario to separate model groups
# ============================================================================
puts "+" + "="*68 + "+"
puts "|" + " "*27 + "PHASE 1" + " "*35 + "|"
puts "|" + " "*17 + "Import Individual Scenarios" + " "*24 + "|"
puts "+" + "="*68 + "+"
puts ""

log "\n" + "="*70, log_file
log "PHASE 1: Individual Scenario Import", log_file
log "="*70, log_file

successful_imports     = []
failed_imports         = []
imported_model_groups  = {}
cleanup_stats          = { label_lists_found: 0, label_lists_deleted: 0, label_lists_kept: 0 }

scenarios.each_with_index do |scenario_name, index|
  puts "[#{index + 1}/#{scenarios.length}] #{scenario_name}"
  puts "  " + "-"*66

  log "\n[#{index + 1}/#{scenarios.length}] Processing scenario: #{scenario_name}", log_file
  log "-" * 70, log_file

  begin
    model_group_name = "#{File.basename(file_path, '.mxd')} - #{scenario_name}"
    log "Creating model group: #{model_group_name}", log_file

    begin
      model_group = db.new_model_object('Model Group', model_group_name)
      log "Model group created with ID: #{model_group.id}", log_file
    rescue => e
      if e.message.include?("already exists")
        err = "ERROR: Model group '#{model_group_name}' already exists.\n" +
              "Please delete or rename it before re-running."
        log err, log_file
        puts err
        log_file.close
        exit 1
      else
        raise
      end
    end

    import_log_path = File.join(log_dir, "#{scenario_name}_#{Time.now.strftime('%Y%m%d_%H%M%S')}.txt")
    log "Importing scenario '#{scenario_name}' from #{File.basename(file_path)}...", log_file

    imported_objects = model_group.import_all_sw_model_objects(
      file_path,
      "mxd",
      scenario_name,
      import_log_path
    )

    if imported_objects.nil? || imported_objects.empty?
      puts "  FAILED: No objects imported"
      log "WARNING: No objects imported for scenario '#{scenario_name}'", log_file

      if File.exist?(import_log_path)
        log "Import log contents:", log_file
        File.foreach(import_log_path) { |line| log "  #{line.strip}", log_file }
      end

      failed_imports << scenario_name
      begin
        model_group.delete
        log "Deleted empty model group", log_file
      rescue => e
        log "Could not delete empty model group: #{e.message}", log_file
      end
    else
      puts "  > Imported #{imported_objects.length} objects"
      log "SUCCESS: Imported #{imported_objects.length} objects for scenario '#{scenario_name}'", log_file
      log "Imported objects:", log_file
      imported_objects.each { |obj| log "  - #{obj.type}: #{obj.name} (ID: #{obj.id})", log_file }

      # Cleanup empty label lists
      if cleanup_empty_label_lists
        log "\nCleaning up empty label lists...", log_file
        label_lists_to_delete = []

        imported_objects.each do |obj|
          if obj.type == 'Label List'
            cleanup_stats[:label_lists_found] += 1
            log "  Found Label List: #{obj.name} (ID: #{obj.id})", log_file
            if is_label_list_empty?(obj, log_file)
              log "    Label list is empty - marking for deletion", log_file
              label_lists_to_delete << obj
            else
              log "    Label list has content - keeping", log_file
              cleanup_stats[:label_lists_kept] += 1
            end
          end
        end

        if label_lists_to_delete.any?
          log "  Deleting #{label_lists_to_delete.length} empty label list(s)...", log_file
          puts "  > Cleaning up: #{label_lists_to_delete.length} empty label list(s) removed"
          label_lists_to_delete.each do |label_list|
            begin
              label_list.delete
              cleanup_stats[:label_lists_deleted] += 1
              log "    Deleted: #{label_list.name}", log_file
            rescue => e
              log "    ERROR deleting label list '#{label_list.name}': #{e.message}", log_file
              cleanup_stats[:label_lists_kept] += 1
            end
          end
          log "  Cleanup complete: deleted #{cleanup_stats[:label_lists_deleted]} label lists", log_file
        else
          log "  No empty label lists to clean up", log_file
        end
      end

      # Commit the imported network so it's persisted before Phase 2
      imported_network = imported_objects.find { |o| o.type == 'SWMM network' }

      if imported_network
        begin
          log stamp("Committing imported network: #{imported_network.name}"), log_file
          tmp_net = imported_network.open
          tmp_net&.commit("Imported from InfoSWMM - #{scenario_name}")
          log "Network committed successfully", log_file
        rescue => e
          log "WARNING: Could not commit network: #{e.message}", log_file
        end
      end

      successful_imports << { scenario: scenario_name, group_id: model_group.id, count: imported_objects.length }
      imported_model_groups[scenario_name] = model_group.id
    end

  rescue => e
    puts "  ERROR: #{e.message}"
    log "ERROR importing scenario '#{scenario_name}': #{e.message}", log_file
    log "Backtrace: #{e.backtrace.join("\n")}", log_file
    failed_imports << scenario_name
  end
end

if cleanup_empty_label_lists
  log "\n" + "="*70, log_file
  log "CLEANUP STATISTICS", log_file
  log "="*70, log_file
  log "Label lists found  : #{cleanup_stats[:label_lists_found]}", log_file
  log "Label lists deleted: #{cleanup_stats[:label_lists_deleted]}", log_file
  log "Label lists kept   : #{cleanup_stats[:label_lists_kept]}", log_file
  log "="*70 + "\n", log_file

  if cleanup_stats[:label_lists_deleted] > 0
    puts "\n" + "-" * 70
    puts "  Cleanup Summary: Deleted #{cleanup_stats[:label_lists_deleted]} empty label list(s)"
    puts "-" * 70
  end
end

# ============================================================================
# PHASE 1.5: Deduplicate Rainfall & Inflow Events
# ============================================================================
puts "+" + "="*68 + "+"
puts "|" + " "*26 + "PHASE 1.5" + " "*33 + "|"
puts "|" + " "*10 + "Analyze & Deduplicate Rainfall/Inflow Events" + " "*13 + "|"
puts "+" + "="*68 + "+"
puts ""

log "\n" + "="*70, log_file
log "PHASE 1.5: Object Deduplication Analysis", log_file
log "="*70, log_file

all_objects_by_type   = {}
object_stats_by_type  = {}

DEDUP_OBJECT_TYPES.each do |t|
  all_objects_by_type[t]   = {}
  object_stats_by_type[t]  = { total_found: 0, unique_count: 0, duplicate_count: 0 }
end

successful_imports.each do |import_info|
  scenario_name = import_info[:scenario]
  group_id      = import_info[:group_id]

  model_group = db.model_object_from_type_and_id('Model Group', group_id)
  next unless model_group

  DEDUP_OBJECT_TYPES.each do |obj_type|
    all_objects_by_type[obj_type][scenario_name] = []
    model_group.children.each do |child|
      if child.type == obj_type
        all_objects_by_type[obj_type][scenario_name] << child
        object_stats_by_type[obj_type][:total_found] += 1
      end
    end
    count = all_objects_by_type[obj_type][scenario_name].length
    log "Found #{count} #{obj_type} object(s) in #{scenario_name}", log_file if count > 0
  end
end

unique_objects_by_type = {}

DEDUP_OBJECT_TYPES.each do |obj_type|
  unique_objects_by_type[obj_type] = {}
  next if object_stats_by_type[obj_type][:total_found] == 0

  log "\nAnalyzing #{obj_type}...", log_file
  puts "Analyzing #{obj_type}..."

  all_objects_by_type[obj_type].each do |scenario_name, objects|
    objects.each do |obj|
      obj_model_name = obj.name
      obj_hash       = get_object_hash(obj, log_file)

      if obj_hash.nil?
        log "  WARNING: Could not hash '#{obj_model_name}' from #{scenario_name} - treating as unique", log_file
        unique_key = "UNHASHABLE_#{obj.id}"
      else
        unique_key = obj_hash
      end

      hash_display = obj_hash.nil? ? "FAILED" : "#{obj_hash[0..10]}..."
      log "  '#{obj_model_name}' (#{scenario_name}): hash=#{hash_display}", log_file

      if unique_objects_by_type[obj_type].key?(unique_key)
        object_stats_by_type[obj_type][:duplicate_count] += 1
        unique_objects_by_type[obj_type][unique_key][:scenarios]   << scenario_name
        unique_objects_by_type[obj_type][unique_key][:model_names] << obj_model_name
        log "    -> DUPLICATE (matches '#{unique_objects_by_type[obj_type][unique_key][:model_names].first}')", log_file
      else
        unique_objects_by_type[obj_type][unique_key] = {
          object: obj,
          model_names: [obj_model_name],
          hash: obj_hash,
          scenarios: [scenario_name]
        }
        log "    -> UNIQUE", log_file
      end
    end
  end

  object_stats_by_type[obj_type][:unique_count] = unique_objects_by_type[obj_type].length
end

log "\nDeduplication analysis complete:", log_file
DEDUP_OBJECT_TYPES.each do |obj_type|
  stats = object_stats_by_type[obj_type]
  next if stats[:total_found] == 0
  log "  #{obj_type}:", log_file
  log "    Total found       : #{stats[:total_found]}", log_file
  log "    Unique (by content): #{stats[:unique_count]}", log_file
  log "    Duplicates        : #{stats[:duplicate_count]}", log_file
  puts "  > Found: #{stats[:total_found]} total | Unique: #{stats[:unique_count]} | Duplicates: #{stats[:duplicate_count]}"
end
puts ""

begin
  script_dir = File.dirname(__FILE__)
  tmp_dir    = File.join(script_dir, "temp_object_compare")
  if Dir.exist?(tmp_dir)
    Dir.glob(File.join(tmp_dir, "*")).each { |f| File.delete(f) rescue nil }
    Dir.delete(tmp_dir) rescue nil
    log "Cleaned up temporary object comparison directory", log_file
  end
rescue => e
  log "WARNING: Could not clean up temp directory: #{e.message}", log_file
end

# ============================================================================
# PHASE 2: Create merged network with scenarios
# ============================================================================
merged_group   = nil
merged_network = nil

if merge_scenarios && successful_imports.length > 0
  puts "+" + "="*68 + "+"
  puts "|" + " "*27 + "PHASE 2" + " "*35 + "|"
  puts "|" + " "*14 + "Create Merged Network with Scenarios" + " "*17 + "|"
  puts "+" + "="*68 + "+"
  puts ""

  log "\n" + "="*70, log_file
  log "PHASE 2: Merged Network Creation", log_file
  log "="*70, log_file

  begin
    base_scenario = successful_imports.find { |s| s[:scenario].upcase == 'BASE' }

    if base_scenario.nil?
      base_scenario = successful_imports.first
      log "WARNING: No BASE scenario found, using '#{base_scenario[:scenario]}' as master", log_file
      puts "  WARNING: Using '#{base_scenario[:scenario]}' as master (no BASE found)"
    else
      log "Using BASE scenario as master network", log_file
      puts "  Using BASE as master network"
    end

    merged_group_name = "#{File.basename(file_path, '.mxd')} - Merged Scenarios"
    log "Creating merged model group: #{merged_group_name}", log_file
    puts "Step 1: Creating merged model group '#{merged_group_name}'..."

    begin
      merged_group = db.new_model_object('Model Group', merged_group_name)
      log "Merged group created with ID: #{merged_group.id}", log_file
    rescue => e
      if e.message.include?("already exists")
        err = "ERROR: Model group '#{merged_group_name}' already exists. Delete or rename and retry."
        log err, log_file
        puts err
        log_file.close
        exit 1
      else
        raise
      end
    end

    base_group = db.model_object_from_type_and_id('Model Group', base_scenario[:group_id])
    raise "Could not find BASE model group with ID #{base_scenario[:group_id]}" if base_group.nil?

    base_network = nil
    log "Searching for network in BASE group, children:", log_file
    base_group.children.each do |child|
      log "  - Type: '#{child.type}', Name: '#{child.name}'", log_file
      base_network = child if child.type == 'SWMM network'
      break if base_network
    end

    if base_network.nil?
      child_types = []
      base_group.children.each { |c| child_types << c.type }
      raise "Could not find SWMM network in BASE model group. Found types: #{child_types.join(', ')}"
    end

    log "Found BASE network: #{base_network.name} (ID: #{base_network.id})", log_file

    base_net    = base_network.open
    node_count  = base_net&.row_objects('_nodes')&.length.to_i
    link_count  = base_net&.row_objects('_links')&.length.to_i
    sub_count   = base_net&.row_objects('_subcatchments')&.length.to_i

    log "BASE network contains: #{node_count} nodes, #{link_count} links, #{sub_count} subcatchments", log_file
    raise "BASE network is empty!" if node_count == 0 && link_count == 0

    log "Copying BASE network to merged group...", log_file
    merged_network = merged_group.copy_here(base_network, false, false)
    raise "Failed to copy BASE network - copy_here returned nil" if merged_network.nil?

    merged_network_name = "#{File.basename(file_path, '.mxd')} - Merged"
    merged_network.name = merged_network_name
    log "Copied network as: #{merged_network_name} (ID: #{merged_network.id})", log_file

    merged_net = merged_network.open
    merged_node_count = merged_net&.row_objects('_nodes')&.length.to_i
    merged_link_count = merged_net&.row_objects('_links')&.length.to_i
    merged_sub_count  = merged_net&.row_objects('_subcatchments')&.length.to_i
    log "Merged network after copy: #{merged_node_count} nodes, #{merged_link_count} links, #{merged_sub_count} subcatchments", log_file

    if merged_node_count == 0 && merged_link_count == 0
      log "WARNING: copy_here created empty network, attempting manual commit...", log_file
      merged_net.commit("Initial import from BASE")
      merged_node_count = merged_net&.row_objects('_nodes')&.length.to_i
      raise "Copied network is empty even after commit" if merged_node_count == 0
    end

    log "Successfully created merged network with BASE data", log_file

    # ----- Replace base-copy duplicates with deduplicated unique objects -----
    log "\nDeduplicating objects in merged group...", log_file
    puts "Step 2: Copy unique Rainfall/Inflow Events to merged group"

    total_copied             = 0
    total_failed             = 0
    total_duplicates_skipped = 0

    DEDUP_OBJECT_TYPES.each do |obj_type|
      next if object_stats_by_type[obj_type][:total_found] == 0

      log "\n  Processing #{obj_type}...", log_file

      existing_objects = []
      merged_group.children.each { |child| existing_objects << child if child.type == obj_type }

      log "    Found #{existing_objects.length} existing #{obj_type} object(s) (will be replaced)", log_file
      existing_objects.each do |obj|
        begin
          obj.delete
          log "      Deleted: #{obj.name}", log_file
        rescue => e
          log "      WARNING: Could not delete '#{obj.name}': #{e.message}", log_file
        end
      end

      unique_count = unique_objects_by_type[obj_type].length
      log "    Copying #{unique_count} unique #{obj_type} object(s)...", log_file

      objects_copied = 0
      objects_failed = 0
      object_number  = 1

      unique_objects_by_type[obj_type].each do |unique_key, obj_info|
        obj = obj_info[:object]
        begin
          copied_obj = merged_group.copy_here(obj, false, false)
          new_name   = "#{obj_type} #{object_number.to_s.rjust(2, '0')}"
          copied_obj.name = new_name
          scenario_list   = obj_info[:scenarios].join("\r\n")
          begin
            copied_obj.comment = scenario_list
            log "      Copied as: '#{new_name}' (ID: #{copied_obj.id}, scenarios: #{obj_info[:scenarios].join(', ')})", log_file
          rescue => e
            log "      WARNING: Could not set description for '#{new_name}': #{e.message}", log_file
          end
          objects_copied += 1
          object_number  += 1
        rescue => e
          objects_failed += 1
          log "      ERROR copying '#{obj_info[:model_names].first}': #{e.message}", log_file
        end
      end

      duplicates_skipped = object_stats_by_type[obj_type][:duplicate_count]
      log "    #{obj_type} complete: #{objects_copied} copied, #{objects_failed} failed, #{duplicates_skipped} duplicates skipped", log_file
      puts "  > Copied: #{objects_copied} unique | Skipped: #{duplicates_skipped} duplicates"

      total_copied             += objects_copied
      total_failed             += objects_failed
      total_duplicates_skipped += duplicates_skipped
    end

    log "\n  Object deduplication complete:", log_file
    log "    Total objects copied: #{total_copied}", log_file
    log "    Total failed        : #{total_failed}", log_file
    log "    Duplicates skipped  : #{total_duplicates_skipped}", log_file
    puts ""

    # Add other scenarios to merged network
    other_scenarios = successful_imports.reject { |s| s[:scenario] == base_scenario[:scenario] }

    if other_scenarios.any?
      log "\nAdding #{other_scenarios.length} additional scenario(s) to merged network...", log_file
      puts "Step 3: Add #{other_scenarios.length} scenario(s) to merged network"

      merged_net_work = merged_network.open

      other_scenarios.each_with_index do |scenario_info, idx|
        scenario_name = scenario_info[:scenario]
        puts "  [#{idx + 1}/#{other_scenarios.length}] #{scenario_name}"
        log "\nAdding scenario: #{scenario_name}", log_file

        begin
          scenario_group = db.model_object_from_type_and_id('Model Group', scenario_info[:group_id])
          raise "Could not find model group for scenario #{scenario_name}" if scenario_group.nil?

          selection_list = nil
          scenario_group.children.each do |child|
            if child.type == 'Selection List'
              log "  Found Selection List: #{child.name} (ID: #{child.id})", log_file
              selection_list = child
              break
            end
          end

          if selection_list.nil?
            log "  WARNING: No selection list found for scenario #{scenario_name}", log_file
            puts "    WARNING: No selection list found - skipping"
            next
          end

          source_network = nil
          scenario_group.children.each do |child|
            source_network = child if child.type == 'SWMM network'
            break if source_network
          end

          if source_network.nil?
            log "  WARNING: No SWMM network found - skipping", log_file
            next
          end

          merged_net_work.current_scenario = 'Base'
          merged_net_work.add_scenario(scenario_name, 'Base', "Imported from InfoSWMM - #{scenario_name}")
          merged_net_work.current_scenario = scenario_name

          source_net = source_network.open
          fields_updated = 0
          fields_skipped = 0

          merged_net_work.transaction_begin

          # ---- Copy node data (scalar fields + sub-table blobs) ----
          node_blobs = {
            'additional_dwf'    => %w[baseline bf_pattern_1 bf_pattern_2 bf_pattern_3 bf_pattern_4],
            'pollutant_dwf'     => %w[pollutant],
            'treatment'         => %w[pollutant result function],
            'pollutant_inflows' => %w[pollutant]
          }
          source_net.row_objects('_nodes').each do |source_node|
            target_node = merged_net_work.row_object('_nodes', source_node.id)
            next unless target_node
            source_node.table_info.fields.each do |field|
              field_name = field.name
              next if field_name.downcase == 'node_id'
              begin
                src_v = source_node[field_name]
                dst_v = target_node[field_name]
                if src_v != dst_v
                  target_node[field_name] = src_v
                  fields_updated += 1
                end
              rescue => e
                fields_skipped += 1
                log "    Skipped node field '#{field_name}': #{e.message}", log_file if fields_skipped <= 10
              end
            end

            node_blobs.each do |blob_name, sub_fields|
              begin
                src_struct = source_node[blob_name]
                dst_struct = target_node[blob_name]
                src_rows = []
                src_struct.each do |row|
                  row_data = {}
                  sub_fields.each { |fn| row_data[fn] = row[fn] rescue nil }
                  src_rows << row_data
                end
                dst_struct.size = src_rows.length
                src_rows.each_with_index do |row_data, i|
                  sub_fields.each { |fn| begin; dst_struct[i][fn] = row_data[fn]; rescue; end }
                end
                dst_struct.write
              rescue => e
                log "    Skipped blob '#{blob_name}' for node #{source_node.id}: #{e.message}", log_file
              end
            end

            target_node.write
          end
          log "  Node fields: #{fields_updated} updated, #{fields_skipped} skipped", log_file

          # ---- Copy link data ----
          link_fields_updated = 0
          link_fields_skipped = 0
          source_net.row_objects('_links').each do |source_link|
            target_link = merged_net_work.row_object('_links', source_link.id)
            next unless target_link
            source_link.table_info.fields.each do |field|
              field_name = field.name
              next if ['link_id', 'us_node_id', 'ds_node_id'].include?(field_name.downcase)
              begin
                src_v = source_link[field_name]
                dst_v = target_link[field_name]
                if src_v != dst_v
                  target_link[field_name] = src_v
                  link_fields_updated += 1
                end
              rescue => e
                link_fields_skipped += 1
                log "    Skipped link field '#{field_name}': #{e.message}", log_file if link_fields_skipped <= 10
              end
            end
            target_link.write
          end
          log "  Link fields: #{link_fields_updated} updated, #{link_fields_skipped} skipped", log_file

          # ---- Copy subcatchment data ----
          sub_fields_updated = 0
          sub_fields_skipped = 0
          source_net.row_objects('_subcatchments').each do |source_sub|
            target_sub = merged_net_work.row_object('_subcatchments', source_sub.id)
            next unless target_sub
            source_sub.table_info.fields.each do |field|
              field_name = field.name
              next if field_name.downcase == 'subcatchment_id'
              begin
                src_v = source_sub[field_name]
                dst_v = target_sub[field_name]
                if src_v != dst_v
                  target_sub[field_name] = src_v
                  sub_fields_updated += 1
                end
              rescue => e
                sub_fields_skipped += 1
                log "    Skipped sub field '#{field_name}': #{e.message}", log_file if sub_fields_skipped <= 10
              end
            end
            target_sub.write
          end
          log "  Subcatchment fields: #{sub_fields_updated} updated, #{sub_fields_skipped} skipped", log_file

          # ---- Copy rain gage data ----
          gage_fields_updated = 0
          gage_fields_skipped = 0
          source_net.row_objects('sw_raingage').each do |source_gage|
            target_gage = merged_net_work.row_object('sw_raingage', source_gage.id)
            next unless target_gage
            source_gage.table_info.fields.each do |field|
              field_name = field.name
              next if field_name.downcase == 'raingage_id'
              begin
                src_v = source_gage[field_name]
                dst_v = target_gage[field_name]
                if src_v != dst_v
                  target_gage[field_name] = src_v
                  gage_fields_updated += 1
                end
              rescue => e
                gage_fields_skipped += 1
                log "    Skipped gage field '#{field_name}': #{e.message}", log_file if gage_fields_skipped <= 10
              end
            end
            target_gage.write
          end
          log "  Rain gage fields: #{gage_fields_updated} updated, #{gage_fields_skipped} skipped", log_file

          # ---- Copy curve and transect tables ----
          aux_tables = {
            'sw_curve_control'    => { 'data'          => %w[variable setting] },
            'sw_curve_pump'       => { 'pump1_data'    => %w[volume_increment outflow],
                                       'pump2_data'    => %w[depth_increment outflow],
                                       'pump3_data'    => %w[head_difference outflow],
                                       'pump4_data'    => %w[continuous_depth outflow] },
            'sw_curve_rating'     => { 'data'          => %w[head outflow] },
            'sw_curve_shape'      => { 'data'          => %w[normalized_depth normalized_width] },
            'sw_curve_tidal'      => { 'data'          => %w[hour elevation] },
            'sw_curve_storage'    => { 'data'          => %w[depth surface_area] },
            'sw_curve_weir'       => { 'data'          => %w[head coefficient],
                                       'sideflow_data' => %w[head coefficient] },
            'sw_curve_underdrain' => { 'data'          => %w[depth factor] },
            'sw_transect'         => { 'profile'       => %w[x z] }
          }
          aux_updated = 0
          aux_skipped = 0
          aux_tables.each do |table_name, blobs|
            source_net.row_objects(table_name).each do |src_obj|
              dst_obj = merged_net_work.row_object(table_name, src_obj.id)
              next unless dst_obj
              src_obj.table_info.fields.each do |field|
                field_name = field.name
                next if field_name.downcase == 'id'
                begin
                  src_val = src_obj[field_name]
                  dst_val = dst_obj[field_name]
                  if src_val != dst_val
                    dst_obj[field_name] = src_val
                    aux_updated += 1
                  end
                rescue
                  aux_skipped += 1
                end
              end
              blobs.each do |blob_name, sub_fields|
                begin
                  src_blob = src_obj[blob_name]
                  dst_blob = dst_obj[blob_name]
                  src_rows = []
                  src_blob.each do |row|
                    row_data = {}
                    sub_fields.each { |fn| row_data[fn] = row[fn] rescue nil }
                    src_rows << row_data
                  end
                  dst_blob.size = src_rows.length
                  src_rows.each_with_index do |row_data, i|
                    sub_fields.each { |fn| begin; dst_blob[i][fn] = row_data[fn]; rescue; end }
                  end
                  dst_blob.write
                rescue => e
                  log "    Skipped blob '#{blob_name}' for #{table_name} #{src_obj.id}: #{e.message}", log_file
                end
              end
              dst_obj.write
            end
          end
          log "  Auxiliary tables (curves/transects): #{aux_updated} fields updated, #{aux_skipped} skipped", log_file

          # ---- Copy unit hydrograph (RDII) data ----
          uh_group_updated = 0
          source_net.row_objects('sw_uh_group').each do |src_obj|
            dst_obj = merged_net_work.row_object('sw_uh_group', src_obj.id)
            next unless dst_obj
            src_obj.table_info.fields.each do |field|
              field_name = field.name
              next if field_name.downcase == 'id'
              begin
                src_val = src_obj[field_name]
                dst_val = dst_obj[field_name]
                if src_val != dst_val
                  dst_obj[field_name] = src_val
                  uh_group_updated += 1
                end
              rescue; end
            end
            dst_obj.write
          end
          log "  sw_uh_group: #{uh_group_updated} fields updated", log_file

          uh_updated = 0
          source_net.row_objects('sw_uh').each do |src_obj|
            dst_obj = merged_net_work.row_object('sw_uh', src_obj.id)
            next unless dst_obj
            src_obj.table_info.fields.each do |field|
              field_name = field.name
              next if %w[group_id month].include?(field_name.downcase)
              begin
                src_val = src_obj[field_name]
                dst_val = dst_obj[field_name]
                if src_val != dst_val
                  dst_obj[field_name] = src_val
                  uh_updated += 1
                end
              rescue; end
            end
            dst_obj.write
          end
          log "  sw_uh: #{uh_updated} fields updated", log_file

          total_fields  = fields_updated + link_fields_updated + sub_fields_updated +
                          gage_fields_updated + aux_updated + uh_group_updated + uh_updated
          total_skipped = fields_skipped + link_fields_skipped + sub_fields_skipped +
                          gage_fields_skipped + aux_skipped
          log "  TOTAL: #{total_fields} field values updated, #{total_skipped} skipped", log_file

          merged_net_work.transaction_commit
          log "  Field update transaction committed", log_file
          puts "             - Copied #{total_fields} field values" if total_fields > 0

          # ---- Use selection list to determine active elements ----
          merged_net_work.load_selection(selection_list)

          active_nodes = []
          active_links = []
          active_subs  = []
          merged_net_work.row_objects_selection('_nodes').each       { |n| active_nodes << n.id }
          merged_net_work.row_objects_selection('_links').each       { |l| active_links << l.id }
          merged_net_work.row_objects_selection('_subcatchments').each { |s| active_subs  << s.id }

          merged_net_work.clear_selection

          inactive_count = 0
          merged_net_work.row_objects('_nodes').each do |node|
            unless active_nodes.include?(node.id)
              node.selected = true
              inactive_count += 1
            end
          end
          merged_net_work.row_objects('_links').each do |link|
            unless active_links.include?(link.id)
              link.selected = true
              inactive_count += 1
            end
          end
          merged_net_work.row_objects('_subcatchments').each do |sub|
            unless active_subs.include?(sub.id)
              sub.selected = true
              inactive_count += 1
            end
          end

          log "  Selected #{inactive_count} inactive elements for deletion", log_file

          if inactive_count > 0
            merged_net_work.delete_selection
            log "  Successfully deleted inactive elements from scenario '#{scenario_name}'", log_file
            puts "             - Removed #{inactive_count} inactive elements"
          else
            log "  No inactive elements to delete from scenario '#{scenario_name}'", log_file
            puts "             - All elements active"
          end

          merged_net_work.clear_selection
          log "  Scenario '#{scenario_name}' complete", log_file

        rescue => e
          log "ERROR adding scenario '#{scenario_name}': #{e.message}", log_file
          log "Backtrace: #{e.backtrace.join("\n")}", log_file
          puts "             ERROR: #{e.message}"
          begin
            merged_net_work.transaction_rollback
          rescue
            # may not be active
          end
        end
      end

      puts ""
      puts stamp("Step 3: Saving all changes to database")
      log "\nCommitting all scenario changes...", log_file
      merged_net_work.commit("Imported #{other_scenarios.length} scenarios from InfoSWMM")
      log "All changes committed successfully", log_file
    end

    log "\nMerged network creation complete!", log_file

    # Validate scenarios before closing
    log "Validating all scenarios...", log_file
    all_scenarios = ['Base'] + other_scenarios.map { |s| s[:scenario] }
    if merged_net_work
      merged_net_work.validate(all_scenarios)
      log "All scenarios validated successfully", log_file
      merged_net_work.commit("Validated all scenarios")
      log "Validation results committed", log_file
      merged_network_id = merged_network.id
      merged_net_work.close
      merged_net_work = nil
      log "Merged network closed (ID: #{merged_network_id})", log_file
    end

    puts ""
    puts "+" + "="*68 + "+"
    puts "|" + " "*19 + "Merged Network Complete!" + " "*24 + "|"
    puts "+" + "="*68 + "+"

    # ========================================================================
    # PHASE 2.5: Copy SWMM Runs to Merged Network
    # ========================================================================
    if copy_swmm_runs
      puts ""
      puts "+" + "="*68 + "+"
      puts "|" + " "*26 + "PHASE 2.5" + " "*33 + "|"
      puts "|" + " "*17 + "Set Up SWMM Runs for Scenarios" + " "*20 + "|"
      puts "+" + "="*68 + "+"
      puts ""

      log "\n" + "="*70, log_file
      log "PHASE 2.5: SWMM Run Setup", log_file
      log "="*70, log_file

      swmm_runs_created = 0
      swmm_runs_failed  = 0

      begin
        log "Reloading merged model group reference...", log_file
        merged_group = db.model_object_from_type_and_id('Model Group', merged_group.id)
        raise "Could not reload merged model group" if merged_group.nil?

        successful_imports.each_with_index do |import_info, idx|
          scenario_name = import_info[:scenario]
          puts "  [#{idx + 1}/#{successful_imports.length}] #{scenario_name}"
          log "\nProcessing SWMM run for scenario: #{scenario_name}", log_file

          begin
            source_group = db.model_object_from_type_and_id('Model Group', import_info[:group_id])
            raise "Could not find source model group for #{scenario_name}" if source_group.nil?

            source_run = nil
            source_group.children.each do |child|
              source_run = child if child.type == 'SWMM run'
              break if source_run
            end

            if source_run.nil?
              log "  WARNING: No SWMM Run found in #{scenario_name} model group", log_file
              puts "    WARNING: No SWMM Run found - skipping"
              swmm_runs_failed += 1
              next
            end

            log "  Found source run: #{source_run.name} (ID: #{source_run.id})", log_file

            run_builder = WSSWMMRunBuilder.new

            model_basename = File.basename(file_path, '.mxd')
            new_run_name   = "#{model_basename} - #{scenario_name}"
            run_builder['name']    = new_run_name
            run_builder['network'] = merged_network.id

            if scenario_name.upcase != 'BASE'
              run_builder['scenarios'] = [scenario_name]
            else
              run_builder['scenarios'] = ['Base']
            end

            log "  NOTE: API limitations prevent copying timestep controls and other parameters", log_file
            log "        from original runs. Climatology/time patterns must be set manually.", log_file

            # Find rainfall event in merged group via Description match
            merged_rainfall = nil
            merged_group.children.each do |child|
              if child.type == 'Rainfall Event'
                begin
                  description = child.comment || ""
                  if description.include?(scenario_name)
                    merged_rainfall = child
                    break
                  end
                rescue => e
                  log "  WARNING: Could not read description from '#{child.name}': #{e.message}", log_file
                end
              end
            end

            if merged_rainfall
              run_builder['rainfall'] = [merged_rainfall.id]
              log "  Linked to rainfall event: #{merged_rainfall.name} (ID: #{merged_rainfall.id})", log_file
            else
              merged_group.children.each do |child|
                if child.type == 'Rainfall Event'
                  merged_rainfall = child
                  break
                end
              end
              if merged_rainfall
                run_builder['rainfall'] = [merged_rainfall.id]
                log "  WARNING: Using fallback rainfall: #{merged_rainfall.name}", log_file
              else
                log "  WARNING: No rainfall event found - run will use source rainfall", log_file
              end
            end

            # Find inflow in merged group via Description match
            merged_inflow = nil
            merged_group.children.each do |child|
              if child.type == 'Inflow'
                begin
                  description = child.comment || ""
                  if description.include?(scenario_name)
                    merged_inflow = child
                    break
                  end
                rescue => e
                  log "  WARNING: Could not read description from inflow '#{child.name}': #{e.message}", log_file
                end
              end
            end

            if merged_inflow
              begin
                run_builder['inflow'] = [merged_inflow.id]
                log "  Linked to inflow: #{merged_inflow.name} (ID: #{merged_inflow.id})", log_file
              rescue => e
                log "  ERROR: Could not set inflow parameter: #{e.message}", log_file
              end
            else
              log "  No inflow found for #{scenario_name} in merged group (may not be used)", log_file
            end

            log "  Final run configuration:", log_file
            log "    - Name     : #{run_builder['name']}", log_file
            log "    - Network  : #{run_builder['network']}", log_file
            log "    - Scenarios: #{run_builder['scenarios'].inspect}", log_file
            log "    - Rainfall : #{run_builder['rainfall'].inspect}", log_file
            log "    - Inflow   : #{run_builder['inflow'].inspect}", log_file

            begin
              is_valid = run_builder.validate
              log(is_valid ? "  Run parameters validated successfully" : "  WARNING: Run validation found issues", log_file)
            rescue => e
              log "  WARNING: Could not validate run parameters: #{e.message}", log_file
            end

            if run_builder.create_new_run(merged_group.id)
              new_run = run_builder.get_run_mo
              log "  Created SWMM run: #{new_run_name} (ID: #{new_run.id})", log_file

              verify_builder = WSSWMMRunBuilder.new
              if verify_builder.load(new_run)
                log "  Verification of created run:", log_file
                log "    - Name     : #{verify_builder['name']}", log_file
                log "    - Network  : #{verify_builder['network']}", log_file
                log "    - Scenarios: #{verify_builder['scenarios'].inspect}", log_file
                log "    - Rainfall : #{verify_builder['rainfall'].inspect}", log_file
                log "    - Inflow   : #{verify_builder['inflow'].inspect}", log_file
              end

              puts "    Created: #{new_run_name}"
              swmm_runs_created += 1
            else
              log "  ERROR: Failed to create run for #{scenario_name}", log_file
              puts "    ERROR: Failed to create run"
              swmm_runs_failed += 1
            end

          rescue => e
            log "  ERROR processing run for #{scenario_name}: #{e.message}", log_file
            log "  Backtrace: #{e.backtrace.first(5).join("\n           ")}", log_file
            puts "    ERROR: #{e.message}"
            swmm_runs_failed += 1
          end
        end

        log "\nPhase 2.5 complete:", log_file
        log "  SWMM runs created: #{swmm_runs_created}", log_file
        log "  SWMM runs failed : #{swmm_runs_failed}", log_file

        puts ""
        puts "+" + "="*68 + "+"
        puts "|" + " "*20 + "SWMM Runs Created!" + " "*27 + "|"
        puts "+" + "="*68 + "+"

      rescue => e
        log "ERROR in Phase 2.5: #{e.message}", log_file
        log "Backtrace: #{e.backtrace.join("\n")}", log_file
        puts "WARNING: SWMM run setup encountered errors"
      end
    end

  rescue => e
    log "ERROR creating merged network: #{e.message}", log_file
    log "Backtrace: #{e.backtrace.join("\n")}", log_file

    if defined?(merged_group) && merged_group
      begin
        log "Attempting to clean up partial merged network...", log_file
        merged_group.delete
        log "Successfully deleted partial merged network", log_file
      rescue => cleanup_error
        log "Warning: Could not delete partial merged network: #{cleanup_error.message}", log_file
      end
    end
    puts "ERROR: Merged network creation failed"
    puts "  #{e.message}"
  end
end

# ----------------------------------------------------------------------------
# Update Config with Model Group IDs (for DWF Supplement Script)
# ----------------------------------------------------------------------------
begin
  updated_config = nil
  File.open(config_file, 'r') { |f| updated_config = JSON.parse(f.read) }

  scenario_group_ids = {}
  successful_imports.each { |info| scenario_group_ids[info[:scenario]] = info[:group_id] }
  updated_config['scenario_group_ids'] = scenario_group_ids
  updated_config['merged_group_id']    = merged_group.id if defined?(merged_group) && merged_group

  File.open(config_file, 'w') { |f| f.write(JSON.pretty_generate(updated_config)) }
  log "Config updated with model group IDs (for DWF supplement script)", log_file
rescue => e
  log "WARNING: Could not update config with group IDs: #{e.message}", log_file
end

# ----------------------------------------------------------------------------
# Generate Summary
# ----------------------------------------------------------------------------
log "\n" + "="*70, log_file
log "IMPORT, CLEANUP, AND MERGE SUMMARY", log_file
log "="*70, log_file
log "\nPhase 1 - Individual Scenario Imports:", log_file
log "  Successful: #{successful_imports.length}", log_file
log "  Failed    : #{failed_imports.length}", log_file if failed_imports.any?

if successful_imports.any?
  successful_imports.each { |info| log "    - #{info[:scenario]} (#{info[:count]} objects)", log_file }
end

if failed_imports.any?
  log "\n  Failed scenarios:", log_file
  failed_imports.each { |s| log "    - #{s}", log_file }
end

if cleanup_stats[:label_lists_found] > 0
  log "\nCleanup - Empty Label Lists:", log_file
  log "  Found  : #{cleanup_stats[:label_lists_found]}", log_file
  log "  Deleted: #{cleanup_stats[:label_lists_deleted]}", log_file
  log "  Kept   : #{cleanup_stats[:label_lists_kept]}", log_file
end

if DEDUP_OBJECT_TYPES.any? { |type| object_stats_by_type[type][:total_found] > 0 }
  log "\nPhase 1.5 - Object Deduplication:", log_file
  DEDUP_OBJECT_TYPES.each do |obj_type|
    stats = object_stats_by_type[obj_type]
    next if stats[:total_found] == 0
    log "  #{obj_type}: total=#{stats[:total_found]}, unique=#{stats[:unique_count]}, dup=#{stats[:duplicate_count]}", log_file
  end
end

if merge_scenarios && successful_imports.length > 0
  log "\nPhase 2 - Merged Network: created with #{successful_imports.length} scenario(s)", log_file
end

if copy_swmm_runs && defined?(swmm_runs_created)
  log "\nPhase 2.5 - SWMM Runs created: #{swmm_runs_created}", log_file
end

log "\n" + "="*70, log_file
log stamp("All operations completed!"), log_file
log "Log file: #{log_filename}", log_file
log "="*70, log_file

puts ""
puts "+" + "="*68 + "+"
puts "|" + " "*25 + "IMPORT COMPLETE" + " "*28 + "|"
puts "+" + "="*68 + "+"
puts ""
puts "Log file: #{log_filename}"

rescue SystemExit, Interrupt
  raise
rescue => e
  err  = "\n" + "="*70 + "\n"
  err += "FATAL ERROR: Import failed\n"
  err += "="*70 + "\n"
  err += "Error: #{e.class} - #{e.message}\n"
  err += "\nStack trace:\n"
  err += (e.backtrace || []).first(10).join("\n")
  err += "\n" + "="*70 + "\n"
  puts err
  log err, log_file if log_file && !log_file.closed?
ensure
  # Always close any merged network we may have left open
  if merged_net_work
    begin
      merged_net_work.close
    rescue
      # may already be closed
    end
  end

  # Always close the log file
  if log_file && !log_file.closed?
    begin
      log_file.close
    rescue
      # ignore
    end
  end

  puts stamp("Script terminated")
end

exit(defined?(failed_imports) && failed_imports.any? ? 1 : 0)
