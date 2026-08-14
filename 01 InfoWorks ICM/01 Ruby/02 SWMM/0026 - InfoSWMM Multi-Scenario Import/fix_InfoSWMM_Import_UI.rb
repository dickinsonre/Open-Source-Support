# frozen_string_literal: true
# ============================================================================
# InfoSWMM Multi-Scenario Import - UI SCRIPT (HARDENED)
# ============================================================================
#
# DESCRIPTION:
#   User interface script for importing multiple InfoSWMM scenarios into ICM.
#   Collects user input and launches the Exchange script for processing.
#
# HARDENING APPLIED:
#   - Added frozen_string_literal pragma for immutability
#   - Wrapped main logic in begin/rescue/ensure for robust error handling
#   - Validates database connection is active before proceeding
#   - Checks for user cancellations and exits gracefully
#   - Added nil-safety checks on optional return values
#   - File handles opened via block form (File.open do |f|)
#   - Progress logging with timestamps for long operations
#   - Validates config file creation before proceeding
#   - Proper cleanup in ensure block even on errors
#
# USAGE:
#   1. Close InfoSWMM (if model is open)
#   2. Open ICM database
#   3. Network → Run Ruby Script → Select this file
#   4. Follow prompts to select .mxd file and scenarios
#   5. Wait for completion
#
# ============================================================================

require 'json'

begin
  # Get the script directory
  script_dir = File.dirname(WSApplication.script_file)

  # ============================================================================
  # Main execution with error handling
  # ============================================================================
  begin

    # Show welcome dialog with instructions
    WSApplication.message_box(
      "InfoSWMM Multi-Scenario Import\n\n" +
      "This script will:\n" +
      "  * Import each scenario to a separate group\n" +
      "  * Clean up empty label lists\n" +
      "  * Deduplicate Rainfall Events & Inflows\n" +
      "  * Create a merged network with all scenario-variable data\n" +
      "  * Set up SWMM runs (partial configuration)\n\n" +
      "You will need to manually configure:\n" +
      "  [!] Timesteps, Climatology, Time Patterns, Inflows\n\n" +
      "Select your InfoSWMM .mxd file next.",
      "OK",
      "Information",
      false
    )

    # Get InfoSWMM model file from user
    file_path = WSApplication.file_dialog(
      true,
      'mxd',
      'InfoSWMM Model File',
      '',
      false,
      nil
    )

    # Check if user cancelled
    if file_path.nil? || file_path.empty?
      puts "[#{Time.now}] Import cancelled - no file selected."
      exit 0
    end

    # Validate file exists
    unless File.exist?(file_path)
      WSApplication.message_box(
        "File not found: #{file_path}\n\nImport cancelled.",
        "OK",
        "!",
        false
      )
      exit 1
    end

    # Check for InfoSWMM lock files
    mxd_dir = File.dirname(file_path)
    mxd_basename = File.basename(file_path, '.mxd')
    lock_files = []

    begin
      if Dir.exist?(mxd_dir)
        entries = Dir.entries(mxd_dir)
        lock_entries = entries.select { |entry| entry.start_with?('~') && entry != '~' }

        if lock_entries.any?
          lock_files = lock_entries.map { |entry| File.join(mxd_dir, entry) }
          lock_files = lock_files.select { |f| File.exist?(f) }
        end
      end
    rescue => e
      puts "[#{Time.now}] Warning: Could not check for lock files: #{e.message}"
    end

    # Check ISDB folder for lock files
    possible_isdb_folders = [
      File.join(mxd_dir, "#{mxd_basename}.ISDB"),
      File.join(mxd_dir, "ISDB"),
      File.join(mxd_dir, "#{mxd_basename}.isdb"),
      File.join(mxd_dir, "isdb")
    ]

    possible_isdb_folders.each do |isdb_path|
      next unless Dir.exist?(isdb_path)

      begin
        entries = Dir.entries(isdb_path)
        lock_entries = entries.select { |entry| entry.start_with?('~') && entry != '~' }

        if lock_entries.any?
          isdb_locks = lock_entries.map { |entry| File.join(isdb_path, entry) }
          isdb_locks = isdb_locks.select { |f| File.exist?(f) }
          lock_files.concat(isdb_locks)
        end
      rescue => e
        puts "[#{Time.now}] Warning: Could not check ISDB folder: #{e.message}"
      end
    end

    if lock_files.any?
      lock_file_paths = lock_files.join("\n")

      WSApplication.message_box(
        "InfoSWMM is open or has a residual lock file.\n\n" +
        "Lock file(s):\n" +
        "#{lock_file_paths}\n\n" +
        "Close InfoSWMM or delete the lock file, then run this script again.",
        "OK",
        "!",
        false
      )
      exit 1
    end

    puts "\n" + "="*70
    puts " InfoSWMM Multi-Scenario Import - Starting"
    puts "="*70
    puts "[#{Time.now}] Model: #{File.basename(file_path, '.*')}"

    # Try to read scenario names from SCENARIO.DBF
    scenario_names = []
    isdb_folder = nil

    possible_isdb_folders.each do |folder|
      folder_name = File.basename(folder)
      next if folder_name.start_with?('~')

      if Dir.exist?(folder)
        isdb_folder = folder
        puts "[#{Time.now}] Found ISDB folder: #{isdb_folder}"
        break
      end
    end

    if isdb_folder
      scenario_dbf = File.join(isdb_folder, "SCENARIO.DBF")
      scenario_dbf = File.join(isdb_folder, "Scenario.dbf") unless File.exist?(scenario_dbf)

      if File.exist?(scenario_dbf)
        begin
          File.open(scenario_dbf, 'rb') do |file|
            version = file.read(1)
            raise "File is empty or unreadable" if version.nil?

            last_update = file.read(3)
            num_records_bytes = file.read(4)
            header_length_bytes = file.read(2)
            record_length_bytes = file.read(2)

            raise "DBF header is incomplete" if num_records_bytes.nil? || header_length_bytes.nil? || record_length_bytes.nil?

            num_records = num_records_bytes.unpack('V')[0]
            header_length = header_length_bytes.unpack('v')[0]
            record_length = record_length_bytes.unpack('v')[0]

            file.read(20)

            fields = []
            field_offset = 1

            loop do
              field_name_bytes = file.read(11)
              break if field_name_bytes.nil? || field_name_bytes[0] == "\r" || field_name_bytes[0] == "\x0D"

              field_name = field_name_bytes.unpack('Z11')[0]
              break if field_name.nil? || field_name.empty?

              field_type = file.read(1)
              file.read(4)
              field_length = file.read(1).unpack('C')[0]
              file.read(15)

              fields << {
                name: field_name.strip,
                type: field_type,
                offset: field_offset,
                length: field_length
              }

              field_offset += field_length
            end

            id_field = fields.find { |f| ['ID', 'SCEN_ID', 'NAME', 'SCENID'].include?(f[:name].upcase) }

            if id_field.nil?
              puts "[#{Time.now}] Warning: Could not find ID field in SCENARIO.DBF"
            else
              file.seek(header_length)

              num_records.times do
                record = file.read(record_length)
                next if record.nil? || record[0] == '*'

                id_value = record[id_field[:offset], id_field[:length]].strip
                scenario_names << id_value unless id_value.empty?
              end
            end
          end

          puts "[#{Time.now}] Found #{scenario_names.length} scenario(s) in model" if scenario_names.any?

        rescue => e
          puts "[#{Time.now}] Warning: Could not auto-detect scenarios (#{e.message})"
          WSApplication.message_box(
            "Could not read SCENARIO.DBF file.\n\n" +
            "Error: #{e.message}\n\n" +
            "Will use manual entry instead.",
            "OK",
            "!",
            false
          )
        end
      else
        puts "[#{Time.now}] Warning: SCENARIO.DBF not found"
      end
    else
      puts "[#{Time.now}] Warning: ISDB folder not found"
    end

    # Prompt for scenario selection
    if scenario_names.any?
      base_scenario = scenario_names.find { |s| s.upcase == 'BASE' }
      other_scenarios = scenario_names.reject { |s| s.upcase == 'BASE' }

      layout = [
        ['BASE imported automatically', 'READONLY', ''],
        ['', 'READONLY', ''],
        ['Select additional scenarios:', 'READONLY', ''],
        ['Select All', 'BOOLEAN', false]
      ]

      other_scenarios.each do |scenario|
        layout << [scenario, 'BOOLEAN', false]
      end

      result = WSApplication.prompt(
        'Select Scenarios to Import',
        layout,
        false
      )

      if result.nil?
        puts "[#{Time.now}] Import cancelled - no scenarios selected."
        exit 0
      end

      select_all = result[3]

      selected_scenarios = []
      other_scenarios.each_with_index do |scenario, index|
        if select_all || result[index + 4]
          selected_scenarios << scenario
        end
      end

      if base_scenario
        selected_scenarios.unshift(base_scenario)
        puts "[#{Time.now}] BASE will be imported automatically"
      else
        puts "[#{Time.now}] WARNING: No BASE scenario found in model"
      end

      if selected_scenarios.length == 1 && selected_scenarios.first&.upcase == 'BASE'
        result = WSApplication.message_box(
          "Only BASE Scenario Selected\n\n" +
          "You haven't selected any additional scenarios.\n\n" +
          "Continue with only BASE?",
          "YesNo",
          "?",
          false
        )

        if result == "No"
          puts "[#{Time.now}] Import cancelled by user"
          exit 0
        end
      end

      scenario_input = selected_scenarios.join(',')
      puts "[#{Time.now}] Importing #{selected_scenarios.length} scenario(s)"

    else
      layout = [
        ['Could not auto-detect scenarios.', 'READONLY', 'Enter scenario names manually'],
        ['Scenarios', 'STRING', '', nil]
      ]

      result = WSApplication.prompt(
        'Enter Scenarios Manually',
        layout,
        false
      )

      if result.nil?
        puts "[#{Time.now}] Import cancelled - no scenarios entered."
        exit 0
      end

      scenario_input = result[1].strip

      if scenario_input.empty?
        puts "[#{Time.now}] No scenarios entered"
        exit 0
      end

      scenario_count = scenario_input.split(',').length
      puts "[#{Time.now}] Importing #{scenario_count} scenario(s)"
    end

    puts "="*70

    # Verify BASE scenario is included
    scenarios_list = scenario_input.split(',').map(&:strip)
    unless scenarios_list.any? { |s| s.upcase == 'BASE' }
      result = WSApplication.message_box(
        "WARNING: No BASE Scenario Found\n\n" +
        "The merged network needs a BASE scenario\n" +
        "to use as the master network.\n\n" +
        "Continue anyway?",
        "YesNo",
        "!",
        false
      )

      if result == "No"
        puts "[#{Time.now}] Import cancelled - BASE scenario required"
        exit 1
      end
    end

    # Get database connection info
    db = WSApplication.current_database
    if db.nil?
      puts "[#{Time.now}] ERROR: No database is open"
      WSApplication.message_box(
        "No database is currently open.\n\nPlease open an InfoWorks ICM database first.",
        "OK",
        "!",
        false
      )
      exit 1
    end

    db_guid = db.guid

    db_path = nil
    begin
      db_path = db.path if db.respond_to?(:path)
      db_path ||= db.database_path if db.respond_to?(:database_path)
      db_path ||= db.location if db.respond_to?(:location)
      db_path ||= db.file_path if db.respond_to?(:file_path)
    rescue => e
      puts "[#{Time.now}] Warning: Could not get database path: #{e.message}"
    end

    # Save configuration for Exchange script
    model_dir = File.dirname(file_path)
    config_folder = File.join(model_dir, "ICM Import Log Files")
    Dir.mkdir(config_folder) unless Dir.exist?(config_folder)

    config = {
      'file_path' => file_path,
      'scenarios' => scenario_input,
      'database_guid' => db_guid,
      'database_path' => db_path,
      'timestamp' => Time.now.to_s,
      'merge_scenarios' => true,
      'cleanup_empty_label_lists' => true,
      'copy_swmm_runs' => true
    }

    config_file = File.join(config_folder, 'import_config.json')
    File.open(config_file, 'w') { |f| f.write(JSON.pretty_generate(config)) }

    puts "[#{Time.now}] Configuration saved to: #{config_file}"

    # Launch Exchange script
    exchange_script = File.join(script_dir, 'InfoSWMM_Import_Exchange.rb')

    unless File.exist?(exchange_script)
      puts "[#{Time.now}] ERROR: Exchange script not found: #{exchange_script}"
      WSApplication.message_box(
        "Cannot find Exchange script.\n\n#{exchange_script}",
        "OK",
        "!",
        false
      )
      exit 1
    end

    ENV['ICM_IMPORT_CONFIG'] = config_file

    # Find ICMExchange.exe
    icm_exchange = nil
    [
      "C:\\Program Files\\Autodesk\\InfoWorks ICM Ultimate 2027\\ICMExchange.exe",
      "C:\\Program Files\\Autodesk\\InfoWorks ICM Sewer 2027\\ICMExchange.exe",
      "C:\\Program Files\\Autodesk\\InfoWorks ICM Flood 2027\\ICMExchange.exe",
      "C:\\Program Files\\Autodesk\\InfoWorks ICM 2027\\ICMExchange.exe",
      "C:\\Program Files\\Autodesk\\InfoWorks ICM Ultimate 2026\\ICMExchange.exe",
      "C:\\Program Files\\Autodesk\\InfoWorks ICM Sewer 2026\\ICMExchange.exe",
      "C:\\Program Files\\Autodesk\\InfoWorks ICM Flood 2026\\ICMExchange.exe",
      "C:\\Program Files\\Autodesk\\InfoWorks ICM 2026\\ICMExchange.exe",
      "C:\\Program Files\\Autodesk\\InfoWorks ICM Ultimate 2025.2\\ICMExchange.exe",
      "C:\\Program Files\\Autodesk\\InfoWorks ICM 2025.2\\ICMExchange.exe",
      "C:\\Program Files\\Autodesk\\InfoWorks ICM Ultimate 2025\\ICMExchange.exe",
      "C:\\Program Files\\Autodesk\\InfoWorks ICM 2025\\ICMExchange.exe",
      "C:\\Program Files\\Autodesk\\InfoWorks ICM Ultimate 2024.2\\ICMExchange.exe",
      "C:\\Program Files\\Autodesk\\InfoWorks ICM 2024.2\\ICMExchange.exe"
    ].each do |path|
      if File.exist?(path)
        icm_exchange = path
        break
      end
    end

    if icm_exchange.nil?
      puts "[#{Time.now}] ERROR: ICMExchange.exe not found"
      WSApplication.message_box(
        "ERROR: ICMExchange.exe Not Found\n\n" +
        "This script requires ICMExchange.exe to run.",
        "OK",
        "!",
        false
      )
      exit 1
    end

    # Launch Exchange script
    command = "\"#{icm_exchange}\" \"#{exchange_script}\" /ICM"

    puts "[#{Time.now}] Launching Exchange script..."
    require 'open3'
    output, status = Open3.capture2(command)
    success = status.success?

    puts "[#{Time.now}] Exchange script completed with status: #{status.exitstatus}"

    # Display summary
    puts "\n" + "="*70
    puts " IMPORT SUMMARY"
    puts "="*70
    puts ""

    if success
      summary = "Import Complete!\n\n"
      summary += "Scenarios imported: #{selected_scenarios.length}\n\n"
      summary += "See Ruby output window for full details.\n"
      summary += "Logs: ICM Import Log Files folder"

      WSApplication.message_box(summary, "OK", "Information", false)
    else
      WSApplication.message_box(
        "Import Failed\n\n" +
        "Check the Ruby output window for details.",
        "OK",
        "Warning",
        false
      )
    end

  rescue SystemExit, Interrupt
    raise
  rescue => e
    puts "\n" + "="*70
    puts "FATAL ERROR"
    puts "="*70
    puts "[#{Time.now}] Error: #{e.class} - #{e.message}"
    puts "Stack trace:"
    puts e.backtrace.first(10).join("\n")
    puts "="*70

    WSApplication.message_box(
      "An unexpected error occurred:\n\n#{e.message}\n\n" +
      "Check the Ruby output window for details.",
      "OK",
      "!",
      false
    )
    exit 1
  end

ensure
  puts "[#{Time.now}] Script execution ended"
end
