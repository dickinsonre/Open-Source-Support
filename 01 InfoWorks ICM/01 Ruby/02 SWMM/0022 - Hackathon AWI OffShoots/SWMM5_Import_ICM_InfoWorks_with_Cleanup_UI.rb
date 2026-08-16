# ============================================================================
# SWMM5 Import WITH CLEANUP - UI SCRIPT (Version 3.1 - Robust Prompt Fix & Enhancements)
# ============================================================================
# 
# PURPOSE:
#   User-facing script to configure and launch the import of SWMM5 .inp file(s) 
#   into ICM SWMM Networks.
#
# V3.1 CHANGES:
#   - Fixed "attributes parameter item 0 invalid type" RuntimeError by implementing
#     the robust 4-element format [Label, Type, Attributes, DefaultValue] for 
#     all WSApplication.prompt definitions.
#   - Improved relative path naming logic for batch imports.
#   - Enhanced summary reporting with accurate duration formatting (float parsing).
#
# HOW TO USE:
#   1. Open your ICM database.
#   2. Network menu -> Run Ruby Script -> Select this file.
#
# ============================================================================

require 'yaml'
require 'open3'
require 'fileutils'

# Constants
# Robust determination of SCRIPT_DIR
begin
  SCRIPT_DIR = File.dirname(WSApplication.script_file)
rescue
  # Fallback if WSApplication.script_file is not available
  SCRIPT_DIR = File.dirname(__FILE__)
end

EXCHANGE_SCRIPT_NAME = 'SWMM5_Import_ICM_InfoWorks_with_Cleanup_Exchange.rb'
LOG_FOLDER_NAME = "ICM Import Log Files"
TARGET_NETWORK_TYPE = 'SWMM network'

# Networks cannot live at the database root, so every import goes into this
# root-level Model Group. The Exchange script reuses it if it already exists,
# and creates it otherwise. Shown on the confirmation dialogs so it is never a
# surprise where the networks landed.
# Fallback only. The real target is the Model Group of the network open on the
# GeoPlan, worked out in STEP 1 below.
TARGET_MODEL_GROUP = 'SWMM5 Imports'

# Create an empty InfoWorks network beside each imported SWMM network, in the
# same group, named <swmm name> + SHELL_NAME_SUFFIX. A distinct name is
# deliberate (Bob's preference - they ARE different networks), and it sidesteps
# ICM's ghost problem: deleted networks hold their exact names forever, so
# reusing the SWMM name breaks after any delete/reimport cycle. Trade-off: the
# manual conversion dialog only pre-pairs identical names, so pairing is two
# clicks per model. Set the suffix to '' to go back to same-name shells.
CREATE_INFOWORKS_SHELLS = true
SHELL_NAME_SUFFIX = ''

# ----------------------------------------------------------------------------
# Helper: Efficient File Finder
# ----------------------------------------------------------------------------
def find_inp_files(directory, recursive)
  # Normalize path separators
  normalized_directory = directory.gsub('\\', '/')
  
  puts "\nScanning: #{normalized_directory} (Recursive: #{recursive})"
  
  # Use Dir.glob for efficient searching
  pattern = recursive ? File.join(normalized_directory, "**", "*.inp") : File.join(normalized_directory, "*.inp")
  
  files = []
  begin
    # FNM_CASEFOLD for case-insensitive matching (.inp, .INP)
    Dir.glob(pattern, File::FNM_CASEFOLD).each do |file_path|
      files << file_path if File.file?(file_path)
    end
  rescue => e
    puts "ERROR during file scan: #{e.message}"
    WSApplication.message_box("Error Scanning Directory\n\n#{e.message}", "OK", "!", false)
  end
  
  puts "Found #{files.length} files."
  files
end

# ----------------------------------------------------------------------------
# Helper: Find ICMExchange.exe (Robust)
# ----------------------------------------------------------------------------
def find_icm_exchange
  # 1. Hardcoded known paths (newest first)
  known_paths = [
    "C:\\Program Files\\Autodesk\\InfoWorks ICM Ultimate 2027\\ICMExchange.exe",
    "C:\\Program Files\\Autodesk\\InfoWorks ICM 2027\\ICMExchange.exe",
    "C:\\Program Files\\Autodesk\\InfoWorks ICM Ultimate 2026\\ICMExchange.exe",
    "C:\\Program Files\\Autodesk\\InfoWorks ICM 2026\\ICMExchange.exe",
    "C:\\Program Files\\Autodesk\\InfoWorks ICM Ultimate 2025.2\\ICMExchange.exe",
    "C:\\Program Files\\Autodesk\\InfoWorks ICM 2025.2\\ICMExchange.exe",
  ]

  known_paths.each { |path| return path if File.exist?(path) }

  # 2. Dynamic search in Program Files (Autodesk and Innovyze)
  puts "ICMExchange not in known paths. Searching Program Files..."
  ["Autodesk", "Innovyze"].each do |vendor|
    begin
      program_files = ENV['ProgramFiles'] || "C:\\Program Files"
      search_pattern = File.join(program_files, vendor, "InfoWorks ICM*", "ICMExchange.exe")
      # Find the most recent version (sort reverse)
      found_files = Dir.glob(search_pattern.gsub('\\', '/')).sort.reverse
      if found_files.any?
          puts "Found via dynamic search: #{found_files.first}"
          return found_files.first
      end
    rescue
      # Ignore errors during dynamic search
    end
  end

  # 3. User fallback
  WSApplication.message_box(
    "ICMExchange.exe Not Found Automatically\n\n" +
    "Please locate ICMExchange.exe in the InfoWorks ICM installation directory.",
    "OK", "!", false
  )
  
  user_path = WSApplication.file_dialog(true, 'exe', 'Locate ICMExchange.exe', 'ICMExchange.exe', false, nil)
  
  if user_path && File.exist?(user_path) && File.basename(user_path).downcase == 'icmexchange.exe'
    return user_path
  end

  nil
end

# ----------------------------------------------------------------------------
# STEP 1: Initialization and Welcome
# ----------------------------------------------------------------------------
db = WSApplication.current_database
if db.nil?
  WSApplication.message_box("Please open an ICM database before running this script.", "OK", "!", false)
  exit
end

# ----------------------------------------------------------------------------
# Import target = the Model Group holding the network currently open on the
# GeoPlan.
#
# A UI script cannot run without an open network, so that network always
# exists and its group is the obvious destination. It also matches what ICM
# actually does: imported networks land beside the open network regardless of
# which group import_all_sw_model_objects was called on, which is why a
# hard-coded group name was being ignored.
# ----------------------------------------------------------------------------
target_group_name = nil
target_group_id   = nil

begin
  cur_net = WSApplication.current_network
  cur_mo  = cur_net ? cur_net.model_object : nil
  if cur_mo
    parent_group = db.model_object_from_type_and_id(cur_mo.parent_type, cur_mo.parent_id)
    if parent_group
      target_group_name = parent_group.name
      target_group_id   = parent_group.id
      puts "Open network : #{cur_mo.name} (#{cur_mo.type})"
      puts "Import target: Model Group '#{target_group_name}' (id #{target_group_id})"
    end
  end
rescue => e
  puts "Could not determine the open network's group: #{e.message}"
end

if target_group_name.nil?
  WSApplication.message_box(
    "No open network found.\n\n" +
    "Open a network on the GeoPlan first - imported networks go into that " +
    "network's Model Group.",
    "OK", "!", false
  )
  exit
end

result = WSApplication.message_box(
  "SWMM5 Import to ICM (SWMM Networks) - V3.1\n\n" +
  "Features:\n" +
  "  * Single/Batch/Recursive modes\n" +
  "  * Automatic cleanup of empty visualization labels\n" +
  "  * Post-import connectivity validation\n" +
  "  * Live progress streaming\n\n" +
  "Continue?",
  "YesNo", "Information", false
)

exit if result == "No"

# ----------------------------------------------------------------------------
# STEP 2 + 3: Select import mode AND the source file/folder in ONE dialog
# ----------------------------------------------------------------------------
# A dropdown (STRING + 'LIST') is genuinely mutually exclusive - separate
# BOOLEAN checkboxes let the user tick several modes at once, which then had to
# be resolved by an arbitrary "first tick wins" rule.
#
# Both browse buttons live on this same dialog: 'FILE' for the single .inp and
# 'FOLDER' for the batch directory. Only the row matching the chosen mode needs
# filling in - the other is ignored.
import_modes = [
  '1. Single File',
  '2. Batch - Directory Only',
  '3. Batch - Include Subdirectories'
]

layout = [
  # Default to batch on a folder - that is the normal case; single file is the
  # exception.
  ['Import Mode:', 'STRING', import_modes[1], nil, 'LIST', import_modes],
  ['Mode 1 - SWMM5 .inp file:', 'STRING', nil, nil, 'FILE', true, 'inp', 'SWMM5 Input File', false],
  ['Modes 2/3 - folder to scan:', 'STRING', nil, nil, 'FOLDER', 'Select Folder']
]

result = WSApplication.prompt('SWMM5 Import - Source Selection', layout, false)
if result.nil?
  puts "Import cancelled by user"
  exit
end

# The dropdown returns the selected STRING, not an index.
mode_index = import_modes.index(result[0]) || 0
import_mode_label = import_modes[mode_index].sub(/\A\d+\.\s*/, '')
selected_file   = result[1].to_s.strip
selected_folder = result[2].to_s.strip

puts "\n" + "="*70
puts " SWMM5 Import to ICM - V3.1"
puts "="*70
puts "Import Mode: #{import_mode_label}"

file_paths = []
base_directory = nil

case mode_index
when 0 # Single File
  if selected_file.empty?
    WSApplication.message_box(
      "No .inp file selected.\n\nMode 1 (Single File) needs the 'SWMM5 .inp file' row filled in.",
      "OK", "!", false
    )
    exit
  end

  normalized_path = selected_file.gsub('\\', '/')
  unless File.file?(normalized_path)
    WSApplication.message_box("Not a valid file:\n\n#{normalized_path}", "OK", "!", false)
    exit
  end

  file_paths << normalized_path
  base_directory = File.dirname(normalized_path)

when 1, 2 # Batch Modes
  if selected_folder.empty?
    WSApplication.message_box(
      "No folder selected.\n\nModes 2 and 3 need the 'folder to scan' row filled in.",
      "OK", "!", false
    )
    exit
  end

  base_directory = selected_folder.gsub('\\', '/')
  unless File.directory?(base_directory)
    WSApplication.message_box("Not a valid folder:\n\n#{base_directory}", "OK", "!", false)
    exit
  end

  is_recursive = (mode_index == 2)

  file_paths = find_inp_files(base_directory, is_recursive)

  if file_paths.empty?
    WSApplication.message_box("No .inp files found in the selected directory.", "OK", "!", false)
    exit
  end
  
  # Confirmation
  max_display = 20
  file_list = file_paths.take(max_display).map { |f| "  * #{File.basename(f)}" }.join("\n")
  file_list += "\n  ... and #{file_paths.length - max_display} more" if file_paths.length > max_display
  
  result = WSApplication.message_box(
    "Found #{file_paths.length} File(s)\n\n#{file_list}\n\n" +
    "Source folder:\n  #{base_directory}\n\n" +
    "Model Group (from the open network):\n  #{target_group_name}  (id #{target_group_id})\n\n" +
    (CREATE_INFOWORKS_SHELLS ?
      "A blank InfoWorks network named <file>#{SHELL_NAME_SUFFIX} will also be\n" +
      "created for each file, ready for the manual SWMM->InfoWorks conversion.\n\n" : '') +
    "Continue?",
    "YesNo", "?", false
  )
  exit if result == "No"
end

# ----------------------------------------------------------------------------
# STEP 4: Size Check and Time Estimation
# ----------------------------------------------------------------------------
total_size_mb = file_paths.sum { |file| File.exist?(file) ? File.size(file) : 0 } / (1024.0 * 1024.0)

# Timing model calibrated against a real batch run (2026-08-14):
#   86 files, 45.8 MB  ->  134s wall clock (~8.7s of that is ICMExchange startup)
#   per-file import: mean 1.46s, median 0.57s
# The old heuristic assumed 30s PER FILE, which over-predicted by ~20x (it
# quoted ~45 min for a batch that finished in 2.2 min).
EXCHANGE_STARTUP_S = 10.0   # one-off ICMExchange launch cost
PER_FILE_S         = 0.6    # fixed cost per .inp regardless of size
PER_MB_S           = 2.0    # size-driven parse/commit cost

estimated_seconds = EXCHANGE_STARTUP_S +
                    (file_paths.length * PER_FILE_S) +
                    (total_size_mb * PER_MB_S)
estimated_time_minutes = estimated_seconds / 60.0

estimated_time_str = if estimated_seconds < 90
                       "#{estimated_seconds.round} seconds"
                     else
                       "#{estimated_time_minutes.round(1)} minutes"
                     end

puts "Total size: #{total_size_mb.round(2)} MB. Estimated time: ~#{estimated_time_str}"

if estimated_time_minutes > 10
  result = WSApplication.message_box(
    "Large Import Warning\n\nEstimated time: ~#{estimated_time_str}\n\nContinue?",
    "YesNo", "!", false
  )
  exit if result == "No"
end

# ----------------------------------------------------------------------------
# STEP 5: Configure Naming Options
# ----------------------------------------------------------------------------
network_names = []

if mode_index == 0 # Single File
  default_name = File.basename(file_paths.first, '.inp')

  # ICM prompt rows are [Label, Type, DefaultValue] - a 4th element after a
  # BOOLEAN raises "parameters other than default value following BOOLEAN type".
  layout = [
    ['Network Name:', 'STRING', default_name],
    ['Add timestamp?', 'BOOLEAN', false]
  ]
  result = WSApplication.prompt('Import Settings', layout, false)
  exit if result.nil?
  
  # An emptied STRING field comes back as nil, not '' - hence to_s.
  network_name = result[0].to_s.strip
  network_name = default_name if network_name.empty?

  # result[1] holds the boolean value of the checkbox
  if result[1]
    network_name = "#{network_name}_#{Time.now.strftime("%Y%m%d_%H%M")}"
  end
  network_names << network_name
  
else # Batch Modes
    naming_options = [
        '1. Filename Only',
        '2. Directory + Filename (e.g., Dir_File)',
        '3. Relative Path (e.g., Sub_Dir_File)'
    ]

    # A dropdown in ICM is STRING + a 'LIST' attribute, and it returns the
    # selected STRING - not an index.
    layout = [
        ['Naming Convention:', 'STRING', naming_options[0], nil, 'LIST', naming_options],
        # No prefix and no timestamp by default, so the network name matches the
        # .inp filename exactly. That keeps the audit tools' name matching
        # working and lets the InfoWorks shells pair by name.
        ['Prefix (optional):', 'STRING', ''],
        ['Add timestamp?', 'BOOLEAN', false]
    ]
  
    result = WSApplication.prompt('Batch Naming Settings', layout, false)
    exit if result.nil?

    # Retrieve results
    naming_choice = result[0]
    # An emptied STRING field comes back as nil, not '' - hence to_s.
    name_prefix = result[1].to_s.strip
    add_timestamp = result[2]
  
    # Generate names
    timestamp_str = Time.now.strftime("%Y%m%d_%H%M") if add_timestamp
    
    # IMPROVEMENT: Ensure base directory ends with a slash for clean subtraction
    base_dir_normalized = base_directory.end_with?('/') ? base_directory : base_directory + '/'

    file_paths.each do |file_path|
        # Case-insensitive extension removal
        filename = File.basename(file_path, File.extname(file_path))
        
        case naming_choice
        when naming_options[0] # Filename Only
            name = filename
        when naming_options[1] # Directory + Filename
            parent_dir = File.basename(File.dirname(file_path))
            name = "#{parent_dir}_#{filename}"
        when naming_options[2] # Relative Path
            relative_path = file_path.sub(base_dir_normalized, '')
            
            # IMPROVEMENT: Robustly handle files in the root directory
            if relative_path == File.basename(file_path)
                name = filename
            else
                # Construct name from relative path components, replacing separators with underscores
                name = File.join(File.dirname(relative_path), filename).gsub('/', '_')
            end
        else
            # Unrecognised selection - never leave `name` nil for the loop below.
            name = filename
        end
        
        name = "#{name_prefix}#{name}" unless name_prefix.empty?
        name = "#{name}_#{timestamp_str}" if add_timestamp
        
        # Basic sanitization: Replace invalid characters
        name.gsub!(/[^0-9A-Za-z_ -]/, '_')
        network_names << name
    end
  
    # Internal check for self-duplicates
    if network_names.uniq.length != network_names.length
        duplicates = network_names.group_by{|e| e}.select{|k,v| v.size > 1}.keys
        WSApplication.message_box(
            "ERROR: Duplicate Names Generated!\n\n" +
            "The chosen naming convention resulted in duplicate names:\n#{duplicates.take(5).join("\n")}\n\n" +
            "Please adjust the naming options (e.g., enable timestamps or use relative paths) and try again.",
            "OK", "!", false
        )
        exit
    end
end

# ----------------------------------------------------------------------------
# STEP 6: Pre-Validation (Check for Duplicates in DB)
# ----------------------------------------------------------------------------
puts "\nValidating network names against database..."

# Network names are unique DATABASE-WIDE per network type - proven empirically
# by Probe 8 (16 Aug 2026): a virgin name created in one group is refused in
# another ("name already in use"), while the same name across different TYPES
# coexists fine. So the conflict scan must cover the whole tree, not just the
# target group. (An earlier version scoped this to the group - that was wrong.)
#
# Caveat the scan cannot see: DELETED Model Networks still hold their names as
# ghosts. A name can pass this check and still be refused by ICM at creation.
existing_names = {}
scan = []
db.root_model_objects.each { |o| scan << o }
until scan.empty?
  obj = scan.shift
  existing_names[obj.name] = true if obj.type == TARGET_NETWORK_TYPE
  begin
    obj.children.each { |c| scan << c }
  rescue
  end
end
puts "  #{existing_names.size} existing #{TARGET_NETWORK_TYPE}(s) database-wide"

duplicates = network_names.select { |name| existing_names[name] }

if duplicates.any?
  puts "#{duplicates.length} duplicate network name(s) found in the database."

  # A single existing name should NOT cancel the whole batch. Offer to skip just
  # the clashing files, or auto-rename them, and only cancel if asked to.
  dup_actions = [
    "1. Skip the #{duplicates.length} duplicate(s), import the other #{network_names.length - duplicates.length}",
    '2. Auto-rename duplicates (append _2, _3, ...)',
    '3. Cancel the whole import'
  ]

  choice = WSApplication.prompt(
    'Duplicate Network Names',
    [
      ['Name(s) already in use (database-wide):', 'READONLY', duplicates.first(6).join(', ') +
        (duplicates.length > 6 ? " (+#{duplicates.length - 6} more)" : '')],
      ['Importing into:', 'READONLY', "#{target_group_name} (id #{target_group_id})"],
      ['What would you like to do?', 'STRING', dup_actions[0], nil, 'LIST', dup_actions]
    ],
    false
  )
  exit if choice.nil?

  # choice[0] and choice[1] are the two READONLY rows; the dropdown is [2].
  action = dup_actions.index(choice[2]) || 0

  case action
  when 2
    puts 'Import cancelled by user (duplicates).'
    exit

  when 0   # skip the duplicates
    keep = (0...network_names.length).reject { |i| existing_names[network_names[i]] }
    if keep.empty?
      WSApplication.message_box(
        "Every file clashes with an existing network name.\n\nImport cancelled.",
        "OK", "!", false
      )
      exit
    end
    skipped_names = (0...network_names.length).reject { |i| keep.include?(i) }
                                              .map { |i| network_names[i] }
    file_paths    = keep.map { |i| file_paths[i] }
    network_names = keep.map { |i| network_names[i] }
    puts "Skipping #{skipped_names.length}: #{skipped_names.join(', ')}"
    puts "Continuing with #{file_paths.length} file(s)."

  when 1   # auto-rename
    taken = {}
    existing_names.each_key { |k| taken[k] = true }
    renamed = 0
    network_names.each_with_index do |nm, i|
      # Claim the name if it is free, otherwise find a free variant. Prefer
      # ICM's own generator (db.new_network_name, signature proven by Probe 8:
      # type, base, integer, bool -> e.g. "exam1_1") because it also sees the
      # names DELETED networks still hold, which our tree walk cannot.
      unless taken[nm]
        taken[nm] = true
        next
      end

      candidate = begin
        db.new_network_name(TARGET_NETWORK_TYPE, nm, 1, true)
      rescue
        nil
      end

      # Fall back to manual _n suffixing if the generator is unavailable, and
      # guard against the generator handing out a name this batch already took.
      if candidate.nil? || candidate.to_s.strip.empty? || taken[candidate]
        n = 2
        candidate = "#{nm}_#{n}"
        while taken[candidate]
          n += 1
          candidate = "#{nm}_#{n}"
        end
      end

      puts "  renamed '#{nm}' -> '#{candidate}'"
      network_names[i] = candidate
      taken[candidate] = true
      renamed += 1
    end
    puts "Renamed #{renamed} network(s)."
  end
else
  puts "Validation complete. No conflicts found."
end

# ----------------------------------------------------------------------------
# STEP 7: Prepare Configuration File
# ----------------------------------------------------------------------------
config_folder = File.join(base_directory, LOG_FOLDER_NAME)
FileUtils.mkdir_p(config_folder)

file_configs = file_paths.map.with_index do |file_path, index|
  {
    'file_path' => file_path,
    'network_name' => network_names[index],
    'file_basename' => File.basename(file_path)
  }
end

config = {
  'import_mode' => import_mode_label,
  'base_directory' => base_directory,
  'file_configs' => file_configs,
  # Root-level Model Group that will hold the imported networks. The Exchange
  # script reads this key and falls back to 'SWMM5 Imports' if it is absent.
  # Target the Model Group of the network open on the GeoPlan. The id is
  # authoritative; the name is a readable fallback if the id cannot be resolved.
  'import_group_id'   => target_group_id,
  'import_group_name' => target_group_name,
  # Flags for the exchange script
  'cleanup_empty_label_lists' => true,
  'validate_after_import' => true,
  # Run ICM's own net.validate('Base') and only commit networks that pass.
  # Networks with validation ERRORS are left imported but uncommitted.
  'run_icm_validation' => true,
  # Set true to commit invalid networks anyway via commit_bypassing_validation,
  # so nothing is left uncommitted. They are still reported as invalid.
  'commit_even_if_invalid' => false,
  # Also create an empty InfoWorks network beside each import, named
  # <swmm name> + suffix, ready for the manual conversion step.
  'create_infoworks_shells' => CREATE_INFOWORKS_SHELLS,
  'shell_name_suffix' => SHELL_NAME_SUFFIX
}

config_file = File.join(config_folder, 'import_config.yaml')
File.open(config_file, 'w') { |f| f.write(config.to_yaml) }
puts "\nConfiguration saved."

# ----------------------------------------------------------------------------
# STEP 8: Final Confirmation
# ----------------------------------------------------------------------------
result = WSApplication.message_box(
    "Ready to Import #{file_paths.length} File(s)\n\n" +
    "Estimated time: ~#{estimated_time_str}\n\n" +
    "The import will run via ICMExchange. Progress will be streamed LIVE to this Ruby window.\n\n" +
    "Proceed?",
    "YesNo", "?", false
)
exit if result == "No"

# ----------------------------------------------------------------------------
# STEP 9: Launch Exchange Script (Live Streaming)
# ----------------------------------------------------------------------------
exchange_script = File.join(SCRIPT_DIR, EXCHANGE_SCRIPT_NAME)
unless File.exist?(exchange_script)
  WSApplication.message_box("ERROR: Exchange Script Not Found\n#{EXCHANGE_SCRIPT_NAME}", "OK", "!", false)
  exit
end

icm_exchange = find_icm_exchange
if icm_exchange.nil?
  WSApplication.message_box("ERROR: ICMExchange.exe Not Found. Import cancelled.", "OK", "!", false)
  exit
end

# Set Environment Variable and Launch
ENV['ICM_IMPORT_CONFIG'] = config_file
# Ensure paths are properly quoted in the command
command = "\"#{icm_exchange}\" \"#{exchange_script}\" /ICM"

puts "\nLaunching ICMExchange..."
puts "Please wait. Live output streaming below:"
puts "="*70

# Execute the command and stream output
exchange_success = false
begin
  # Use Open3.popen2e to capture both stdout/stderr and stream them live
  Open3.popen2e(command) do |stdin, stdout_and_stderr, wait_thr|
    # Stream output line by line
    stdout_and_stderr.each do |line|
      puts line
    end
    
    # Wait for process to finish and check status
    exit_status = wait_thr.value
    exchange_success = exit_status.success?
    
    puts "="*70
    puts "ICMExchange finished with exit code: #{exit_status.exitstatus}"
  end
rescue => e
  puts "\nERROR launching ICMExchange: #{e.message}"
  WSApplication.message_box("Failed to launch ICMExchange.\n\nError: #{e.message}", "OK", "!", false)
  exit
end

# ----------------------------------------------------------------------------
# STEP 10: Process Results and Display Summary
# ----------------------------------------------------------------------------
puts "\nProcessing results..."
summary_file = File.join(config_folder, "batch_summary.txt")

# Initialize stats. Use a Hash that defaults numeric values to 0.
stats = Hash.new { |h, k| h[k] = 0 }
# Actual destination group(s) reported by the Exchange script, as [path, count]
landed_groups = []

if File.exist?(summary_file)
  begin
    File.readlines(summary_file).each do |line|
      next unless line.include?('=')
      key, value = line.strip.split('=', 2)
      if key == 'landed_group'
        # "path|count" - where ICM actually put the networks
        path, n = value.to_s.split('|')
        landed_groups << [path.to_s, n.to_i]
      elsif key == 'total_duration'
        stats[key] = value.to_f
      else
        stats[key] = value.to_i
      end
    end
  rescue
    puts "WARNING: Error reading summary file."
  end
else
  puts "WARNING: Summary file not found. Check Exchange output above for errors."
end

# Display summary dialog
dialog_title = "Import Complete"
icon = "Information"
summary_msg = ""

if stats['files_failed'] > 0 || stats['files_invalid'] > 0
  dialog_title = "Import Completed with Failures"
  # ICM accepts only '!', '?' and 'Information' as icons - 'Warning' raises
  # RuntimeError: invalid icon. Use '!' for both partial and total failure.
  icon = "!"
end

# IMPROVEMENT: Format duration nicely
if stats['total_duration'] > 0
    duration_str = sprintf('%.2f seconds', stats['total_duration'])
    summary_msg += "Duration: #{duration_str}\n\n"
end

if file_paths.length > 1
  summary_msg += "Batch Results:\n"
  summary_msg += "  Processed: #{stats['files_processed']}\n"
  summary_msg += "  Committed: #{stats['files_successful']}\n"
  summary_msg += "  Failed: #{stats['files_failed']}\n"
  if stats['files_invalid'] > 0
    summary_msg += "  Not committed (validation errors): #{stats['files_invalid']}\n"
  end
  summary_msg += "\n"
else
    if stats['files_successful'] == 1
        summary_msg += "Network Created: #{network_names.first}\n\n"
    elsif stats['files_invalid'] > 0
        summary_msg += "Status: IMPORTED BUT NOT COMMITTED\n" +
                       "Validation reported errors - see the validation report.\n\n"
    else
        summary_msg += "Status: FAILED\n\n"
    end
end
  
if stats['files_successful'] > 0
  summary_msg += "Total Elements Imported:\n"
  summary_msg += "  * #{stats['total_nodes']} nodes\n"
  summary_msg += "  * #{stats['total_links']} links\n"
  summary_msg += "  * #{stats['total_subcatchments']} subcatchments\n\n"
  # The Exchange script writes the 'total_labels_cleaned' key
  if stats['total_labels_cleaned'] > 0
    summary_msg += "Cleaned: #{stats['total_labels_cleaned']} empty visualization labels\n\n"
  end
  if stats['total_warnings'] > 0
    summary_msg += "Validation warnings (committed anyway): #{stats['total_warnings']}\n\n"
  end
end

if stats['shells_created'] > 0 || stats['shells_skipped'] > 0 || stats['shells_failed'] > 0
  summary_msg += "Blank InfoWorks networks: #{stats['shells_created']} created"
  summary_msg += ", #{stats['shells_skipped']} already existed" if stats['shells_skipped'] > 0
  summary_msg += ", #{stats['shells_failed']} failed" if stats['shells_failed'] > 0
  summary_msg += "\n  (use Network > Import > Model > from SWMM network on each)\n\n"
end

unless landed_groups.empty?
  summary_msg += "Networks were placed in:\n"
  landed_groups.each { |path, n| summary_msg += "  #{path}  (#{n})\n" }
  if stats['wrong_group'] > 0
    summary_msg += "\nNOTE: ICM ignored the requested group '#{target_group_name}'\n" +
                   "for #{stats['wrong_group']} network(s) and used the location above.\n"
  end
  summary_msg += "\n"
end

summary_msg += "Detailed logs available in the Ruby output window and:\n#{config_folder}"

WSApplication.message_box(summary_msg, "OK", icon, false)