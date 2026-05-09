# frozen_string_literal: true
# =============================================================================
# PCSWMM to InfoWorks ICM Import Tool - USER INTERFACE (HARDENED)
# =============================================================================
#
# HARDENING APPLIED:
#   - Added frozen_string_literal pragma
#   - Wrapped in begin/rescue/ensure for robust error handling
#   - Validates database is open before proceeding
#   - Nil-safety checks on all user inputs and return values
#   - File handles closed via block form (File.open do |f|)
#   - Config file validation before proceeding
#   - Graceful cancellation handling on user dismissal
#   - Progress logging with timestamps
#   - Cleanup in ensure block
#
# =============================================================================

require 'json'
require 'open3'

begin
  def run_import
    begin
      # Check database is open
      db = WSApplication.current_database

      if db.nil?
        WSApplication.message_box(
          "No database is currently open!\n\n" +
          "Please open an InfoWorks ICM database first.",
          "OK",
          "!",
          false
        )
        return
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

      script_dir = File.dirname(WSApplication.script_file)

      # Get .pcz file from user
      begin
        pcz_file = WSApplication.file_dialog(
          true,
          'pcz',
          'PCSWMM Model Files (*.pcz)',
          '',
          false,
          nil
        )
      rescue Interrupt
        return
      end

      # Validate selection
      if pcz_file.nil? || pcz_file.empty?
        return
      end

      # Validate file exists
      unless File.exist?(pcz_file)
        WSApplication.message_box(
          "File not found:\n#{pcz_file}\n\nImport cancelled.",
          "OK",
          "!",
          false
        )
        return
      end

      # Validate file extension
      unless File.extname(pcz_file).downcase == '.pcz'
        WSApplication.message_box(
          "Invalid file type.\n\nPlease select a PCSWMM .pcz file.\n\nImport cancelled.",
          "OK",
          "!",
          false
        )
        return
      end

      # Get model group name
      model_basename = File.basename(pcz_file, '.pcz')
      default_group_name = "PCSWMM - #{model_basename}"

      group_name = WSApplication.input_box(
        'Model Group Name',
        'Enter name for imported model group:',
        default_group_name
      )

      if group_name.nil? || group_name.strip.empty?
        return
      end

      group_name = group_name.strip

      # Check for duplicate model group
      existing_group = nil
      db.model_object_collection('Model Group')&.each do |mg|
        if mg.name == group_name
          existing_group = mg
          break
        end
      end

      if existing_group
        WSApplication.message_box(
          "Model Group Already Exists\n\n" +
          "A model group named '#{group_name}' already exists.\n\n" +
          "Please delete or rename the existing model group in ICM,\n" +
          "or choose a different name when importing.\n\n" +
          "Import cancelled.",
          "OK",
          "!",
          false
        )
        return
      end

      # Confirm with user
      proceed = WSApplication.message_box(
        "Ready to import PCSWMM model.\n\n" +
        "File: #{File.basename(pcz_file)}\n" +
        "Model Group: #{group_name}\n\n" +
        "Do you want to proceed?",
        "YesNo",
        "?",
        false
      )

      if proceed != "Yes"
        return
      end

      # Prepare configuration
      log_dir = File.dirname(pcz_file)
      config_file = File.join(log_dir, 'pcswmm_import_config.json')

      config = {
        'pcz_file' => pcz_file,
        'model_group_name' => group_name,
        'database_guid' => db_guid,
        'database_path' => db_path
      }

      begin
        File.open(config_file, 'w') { |f| f.write(JSON.pretty_generate(config)) }

        unless File.exist?(config_file) && File.size(config_file) > 0
          raise "Config file was not created properly"
        end
      rescue => e
        WSApplication.message_box(
          "Failed to save configuration file.\n\n" +
          "Error: #{e.message}",
          "OK",
          "!",
          false
        )
        return
      end

      ENV['PCSWMM_IMPORT_CONFIG'] = config_file

      # Find ICMExchange executable
      icm_exchange = nil
      icm_paths = [
        "C:\\Program Files\\Autodesk\\InfoWorks ICM Ultimate 2027\\ICMExchange.exe",
        "C:\\Program Files\\Autodesk\\InfoWorks ICM Sewer 2027\\ICMExchange.exe",
        "C:\\Program Files\\Autodesk\\InfoWorks ICM Flood 2027\\ICMExchange.exe",
        "C:\\Program Files\\Autodesk\\InfoWorks ICM 2027\\ICMExchange.exe",
        "C:\\Program Files\\Autodesk\\InfoWorks ICM Ultimate 2026\\ICMExchange.exe",
        "C:\\Program Files\\Autodesk\\InfoWorks ICM 2026\\ICMExchange.exe",
        "C:\\Program Files\\Autodesk\\InfoWorks ICM Ultimate 2025.2\\ICMExchange.exe",
        "C:\\Program Files\\Autodesk\\InfoWorks ICM 2025.2\\ICMExchange.exe",
        "C:\\Program Files\\Autodesk\\InfoWorks ICM Ultimate 2025\\ICMExchange.exe",
        "C:\\Program Files\\Autodesk\\InfoWorks ICM 2025\\ICMExchange.exe",
        "C:\\Program Files\\Autodesk\\InfoWorks ICM Ultimate 2024.2\\ICMExchange.exe",
        "C:\\Program Files\\Autodesk\\InfoWorks ICM 2024.2\\ICMExchange.exe",
        "C:\\Program Files\\Autodesk\\InfoWorks ICM Ultimate 2024\\ICMExchange.exe",
        "C:\\Program Files\\Autodesk\\InfoWorks ICM 2024\\ICMExchange.exe"
      ]

      icm_paths.each do |path|
        if File.exist?(path)
          icm_exchange = path
          break
        end
      end

      if icm_exchange.nil?
        WSApplication.message_box(
          "ERROR: ICMExchange.exe Not Found\n\n" +
          "This script requires ICMExchange.exe to run.\n\n" +
          "Please contact support or modify the script.",
          "OK",
          "!",
          false
        )
        File.delete(config_file) if File.exist?(config_file)
        return
      end

      exchange_script = File.join(script_dir, 'PCSWMM_Import_Exchange.rb')

      unless File.exist?(exchange_script)
        WSApplication.message_box(
          "Cannot find Exchange script:\n#{exchange_script}\n\n" +
          "Please ensure PCSWMM_Import_Exchange.rb is in the same folder.",
          "OK",
          "!",
          false
        )
        File.delete(config_file) if File.exist?(config_file)
        return
      end

      # Run the import via Exchange script
      puts "\n" + "="*70
      puts "  PCSWMM to InfoWorks ICM Import"
      puts "="*70
      puts ""
      puts "Source: #{File.basename(pcz_file)}"
      puts "Target: #{group_name}"
      puts ""
      puts "[#{Time.now}] Running import..."
      puts ""

      begin
        command = "\"#{icm_exchange}\" \"#{exchange_script}\" /ICM"
        stdout, stderr, status = Open3.capture3(command)
        status_code = status.exitstatus

        sleep(2)

        # Check database to confirm model group was created
        imported_group = nil
        begin
          db.model_object_collection('Model Group')&.each do |mg|
            if mg.name == group_name
              imported_group = mg
              break
            end
          end
        rescue => e
          puts "[#{Time.now}] Error checking database: #{e.message}"
        end

        # Find log files
        pcz_basename = File.basename(pcz_file, '.pcz')
        log_subfolder = File.join(log_dir, pcz_basename)

        latest_log = nil
        latest_inp_log = nil

        if Dir.exist?(log_subfolder)
          log_pattern = File.join(log_subfolder, "PCSWMM_Import_*.log").gsub('\\', '/')
          inp_pattern = File.join(log_subfolder, "INP_Import_*.txt").gsub('\\', '/')

          log_files = Dir.glob(log_pattern)
          latest_log = log_files.max_by { |f| File.mtime(f) }

          inp_log_files = Dir.glob(inp_pattern)
          latest_inp_log = inp_log_files.max_by { |f| File.mtime(f) }
        end

        # Display results
        actual_error = imported_group.nil?

        if !actual_error
          puts "="*70
          puts "IMPORT SUCCESSFUL"
          puts "="*70
          puts ""

          network_obj = nil
          network_name = "Unknown"

          if imported_group
            begin
              imported_group.children&.each do |child|
                if child.type == 'SWMM network'
                  network_obj = child
                  network_name = child.name
                  break
                end
              end
            rescue => e
              puts "[#{Time.now}] Warning: Could not access network: #{e.message}"
            end
          end

          puts "Model Group: #{group_name}"
          puts "Network:     #{network_name}"
          puts ""
          puts "The SWMM network has been imported successfully."
          puts ""
          puts "Log Files:"
          puts "  #{latest_log}" if latest_log
          puts "  #{latest_inp_log}" if latest_inp_log
          puts ""
          puts "="*70

          summary_msg = "Import Successful!\n\n"
          summary_msg += "Network: #{network_name}\n\n"
          summary_msg += "The SWMM network has been imported to:\n#{group_name}"

          WSApplication.message_box(summary_msg, "OK", "Information", false)

        else
          puts "="*70
          puts "IMPORT FAILED"
          puts "="*70
          puts ""

          error_detail = "Model group was not created in the database."

          puts "Error: #{error_detail}"
          puts ""

          if latest_log
            puts "Check log file for details:"
            puts "  #{latest_log}"
          end

          puts ""
          puts "="*70

          error_msg = "Import Failed\n\n"
          error_msg += "#{error_detail}\n\n"

          if latest_log
            error_msg += "Check log file for details:\n#{File.basename(latest_log)}"
          else
            error_msg += "No log file was created."
          end

          WSApplication.message_box(error_msg, "OK", "!", false)
        end

      rescue => e
        puts ""
        puts "="*70
        puts "UNEXPECTED ERROR"
        puts "="*70
        puts ""
        puts "[#{Time.now}] #{e.message}"
        puts ""
        puts "="*70

        WSApplication.message_box(
          "Unexpected Error\n\n#{e.message}",
          "OK",
          "!",
          false
        )
      ensure
        begin
          File.delete(config_file) if config_file && File.exist?(config_file)
        rescue
          # Silently ignore cleanup errors
        end
      end

    rescue SystemExit, Interrupt
      raise
    rescue => e
      puts "[#{Time.now}] Fatal error in run_import: #{e.message}"
      WSApplication.message_box(
        "Fatal Error\n\n#{e.message}",
        "OK",
        "!",
        false
      )
    end
  end

  run_import

ensure
  puts "[#{Time.now}] Script execution completed"
end
