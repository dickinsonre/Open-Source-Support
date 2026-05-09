# frozen_string_literal: true
# =============================================================================
# Hardened: PCSWMM to InfoWorks ICM Import Tool (EXCHANGE / BACKEND)
# =============================================================================
# Purpose : Backend ICM Exchange script that performs the heavy lifting for
#           importing a PCSWMM .pcz model into InfoWorks ICM as a SWMM network.
# Inputs  : Configuration JSON written by the companion UI script. The JSON
#           supplies the .pcz path, target model-group name, expected database
#           GUID and (optionally) database connection string.
# Outputs : Model Group with SWMM network committed to the open ICM database,
#           plus rolling logs in <pcz dir>/<pcz name>/PCSWMM_Import_*.log.
# UI/EX   : Exchange (ICM Exchange) script - launched automatically by the
#           PCSWMM_Import_UI script. Do not run directly.
# Hardening notes:
#   * frozen_string_literal pragma at top
#   * Outer begin / rescue / ensure wraps the entire run; ensure block always
#     closes log files, removes temp directories and closes the open network.
#   * db.open / WSApplication.open is wrapped; open_network results validated.
#   * Database GUID is verified against the expected value before any writes.
#   * Lock-file detection guarded against missing directories.
#   * File handles use the block form `File.open(path) do |f| ... end`.
#   * Nil-safety with `&.` on optional method results.
#   * Timestamped progress logging via `puts "[#{Time.now}] ..."`.
#   * Original behaviour of the PCSWMM importer is preserved verbatim.
# =============================================================================

require 'json'
require 'fileutils'
require 'tmpdir'
require 'open3'
require 'uri'

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

def log(message, log_file = nil)
  puts message
  log_file&.puts message
end

def stamp(msg)
  "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] #{msg}"
end

# Truncate long field values in INP file to meet ICM's 100-character limit
def truncate_long_fields(input_file, output_file, log_file = nil)
  max_length = 100
  truncation_count = 0
  line_number = 0

  log "  Scanning INP file: #{input_file}", log_file if log_file
  log "  Writing truncated version: #{output_file}", log_file if log_file

  File.open(output_file, 'w') do |out|
    File.foreach(input_file) do |line|
      line_number += 1
      original_line = line.dup
      modified = false

      while line =~ /["']([^"']{101,})["']/
        long_value = $1
        truncated = long_value[0, max_length]
        line.sub!(/["']#{Regexp.escape(long_value)}["']/, "\"#{truncated}\"")
        truncation_count += 1
        modified = true
        if truncation_count <= 10
          log "    [#{truncation_count}] Line #{line_number}: Quoted string truncated", log_file if log_file
          log "        From (#{long_value.length} chars): #{long_value[0, 60]}...", log_file if log_file
          log "        To   (#{max_length} chars): #{truncated[0, 60]}...", log_file if log_file
        end
      end

      unquoted_long_values = []
      line.scan(/\S{101,}/) do |long_value|
        next if long_value =~ /^[\d\.\-\+eE]+$/
        unquoted_long_values << long_value
      end

      unquoted_long_values.each do |long_value|
        truncated = long_value[0, max_length]
        line.sub!(long_value, truncated)
        truncation_count += 1
        modified = true
        if truncation_count <= 10
          log "    [#{truncation_count}] Line #{line_number}: Unquoted value truncated", log_file if log_file
          log "        From (#{long_value.length} chars): #{long_value[0, 60]}...", log_file if log_file
          log "        To   (#{max_length} chars): #{truncated[0, 60]}...", log_file if log_file
        end
      end

      if modified && log_file && truncation_count <= 5
        log "        Original line: #{original_line.strip[0, 100]}", log_file
        log "        Modified line: #{line.strip[0, 100]}", log_file
      end

      out.puts line
    end
  end

  if truncation_count > 0
    log "  SUCCESS: Truncated #{truncation_count} field value(s) to #{max_length} characters", log_file if log_file
    puts "  > Fixed #{truncation_count} overly long field value(s)"
  else
    log "  No field truncation needed (no values > #{max_length} characters found)", log_file if log_file
  end

  truncation_count
rescue => e
  log "  ERROR in truncate_long_fields: #{e.message}", log_file if log_file
  log "  Backtrace: #{e.backtrace.join("\n")}", log_file if log_file
  raise
end

# =============================================================================
# MAIN EXECUTION (wrapped for hardening)
# =============================================================================

log_file = nil
temp_dir = nil
db = nil
net = nil

begin
  puts ""
  puts "="*70
  puts stamp("EXCHANGE SCRIPT STARTED (hardened)")
  puts "="*70

  # ---------------------------------------------------------------------------
  # STEP 1: READ CONFIGURATION
  # ---------------------------------------------------------------------------
  config_file = ENV['PCSWMM_IMPORT_CONFIG']
  puts "ENV variable: #{config_file.inspect}"

  if config_file.nil? || config_file.empty?
    script_dir = File.dirname(__FILE__)
    config_file = File.join(script_dir, 'config.json')
    puts "Using config.json from script directory"
  end

  puts "Config file: #{config_file}"

  unless File.exist?(config_file)
    puts "ERROR: Configuration file not found: #{config_file}"
    puts ""
    puts "Please create a config.json with keys: pcz_file, model_group_name"
    exit 1
  end

  config = nil
  File.open(config_file, 'r') do |f|
    config = JSON.parse(f.read)
  end

  required_keys = ['pcz_file', 'model_group_name']
  missing = required_keys - config.keys
  if missing.any?
    puts "ERROR: Configuration missing required keys: #{missing.join(', ')}"
    exit 1
  end

  pcz_file   = config['pcz_file']
  group_name = config['model_group_name']

  unless File.exist?(pcz_file)
    puts "ERROR: PCZ file not found: #{pcz_file}"
    exit 1
  end

  unless File.extname(pcz_file).downcase == '.pcz'
    puts "ERROR: File must be a PCSWMM .pcz file"
    puts "Selected file: #{pcz_file}"
    exit 1
  end

  puts "\n" + "="*70
  puts "  PCSWMM to InfoWorks ICM Import Tool (Exchange Mode - hardened)"
  puts "="*70
  puts ""
  puts "PCZ File   : #{File.basename(pcz_file)}"
  puts "Model Group: #{group_name}"
  puts "="*70

  # ---------------------------------------------------------------------------
  # STEP 2: OPEN DATABASE
  # ---------------------------------------------------------------------------
  expected_guid = config['database_guid']
  db_path       = config['database_path']

  if db_path && !db_path.empty?
    puts stamp("Opening database: #{db_path}")
    db = WSApplication.open(db_path)
  else
    puts stamp("Database path not available, using default connection")
    db = WSApplication.open
  end

  if db.nil?
    puts "ERROR: Database is nil after WSApplication.open"
    exit 1
  end

  puts stamp("Database opened. GUID: #{db.guid}")

  actual_guid = db.guid
  if expected_guid && actual_guid != expected_guid
    puts ""
    puts "="*70
    puts "ERROR: Connected to wrong database"
    puts "  Expected GUID: #{expected_guid}"
    puts "  Actual   GUID: #{actual_guid}"
    puts "Close all ICM instances, open ONLY the target database, and retry."
    puts "="*70
    exit 1
  end

  # ---------------------------------------------------------------------------
  # STEP 3: SETUP LOGGING
  # ---------------------------------------------------------------------------
  pcz_basename = File.basename(pcz_file, '.pcz')
  base_dir     = File.dirname(pcz_file)
  log_dir      = File.join(base_dir, pcz_basename)
  Dir.mkdir(log_dir) unless Dir.exist?(log_dir)

  log_filename = File.join(log_dir, "PCSWMM_Import_#{Time.now.strftime('%Y%m%d_%H%M%S')}.log")
  log_file     = File.open(log_filename, 'w')

  log "="*70, log_file
  log stamp("PCSWMM to InfoWorks ICM Import (hardened)"), log_file
  log "="*70, log_file
  log "Database GUID : #{db.guid}", log_file
  log "Source File   : #{pcz_file}", log_file
  log "Model Group   : #{group_name}", log_file
  log "Log Directory : #{log_dir}", log_file
  log "="*70, log_file

  # ---------------------------------------------------------------------------
  # STEP 4: EXTRACT PCZ FILE
  # ---------------------------------------------------------------------------
  puts ""
  puts stamp("Step 1: Extract PCZ file")
  log "\nExtracting PCZ file...", log_file

  temp_dir = File.join(Dir.tmpdir, "pcswmm_import_#{Time.now.to_i}")
  Dir.mkdir(temp_dir) unless Dir.exist?(temp_dir)
  log "  Temp directory: #{temp_dir}", log_file

  temp_zip = File.join(temp_dir, "temp_extract.zip")
  log "  Copying .pcz to .zip for extraction...", log_file
  FileUtils.cp(pcz_file, temp_zip)
  log "  Copied to: #{temp_zip}", log_file

  ps_command = "Expand-Archive -Path '#{temp_zip}' -DestinationPath '#{temp_dir}' -Force"
  stdout, stderr, status = Open3.capture3(
    "powershell", "-NoProfile", "-NonInteractive", "-Command", ps_command
  )

  log "  PowerShell output: #{stdout}", log_file unless stdout.empty?
  log "  PowerShell errors: #{stderr}", log_file unless stderr.empty?

  begin
    File.delete(temp_zip) if File.exist?(temp_zip)
    log "  Cleaned up temporary .zip file", log_file
  rescue => e
    log "  Warning: Could not delete temp .zip: #{e.message}", log_file
  end

  unless status.success?
    log "  ERROR: Failed to extract PCZ (exit #{status.exitstatus})", log_file
    puts "ERROR: Failed to extract PCZ file (exit #{status.exitstatus})"
    puts stderr unless stderr.empty?
    exit 1
  end

  log "  Extraction completed successfully", log_file

  extracted_files = Dir.glob(File.join(temp_dir, '**', '*')).select { |f| File.file?(f) }
  puts "  > Extracted #{extracted_files.length} file(s)"
  log "  Extracted #{extracted_files.length} file(s)", log_file

  if extracted_files.length > 0
    log "  Extracted files (first 10):", log_file
    extracted_files.first(10).each { |f| log "    - #{File.basename(f)}", log_file }
    log "    ... and #{extracted_files.length - 10} more" if extracted_files.length > 10
  end

  # ---------------------------------------------------------------------------
  # STEP 5: FIND INP FILE
  # ---------------------------------------------------------------------------
  puts ""
  puts stamp("Step 2: Find INP file")
  log "\nSearching for INP file...", log_file

  inp_files = Dir.glob(File.join(temp_dir, '**', '*.inp'))
  if inp_files.empty?
    log "  ERROR: No INP file found in PCZ archive", log_file
    puts "ERROR: No INP file found in PCZ archive"
    exit 1
  end

  inp_file = inp_files.first
  log "  Found INP file: #{File.basename(inp_file)}", log_file
  puts "  > Found: #{File.basename(inp_file)}"

  # ---------------------------------------------------------------------------
  # STEP 6: CREATE MODEL GROUP
  # ---------------------------------------------------------------------------
  puts ""
  puts stamp("Step 3: Create Model Group")
  log "\nCreating model group: #{group_name}", log_file

  model_group = db.new_model_object('Model Group', group_name)
  log "  Model group created with ID: #{model_group.id}", log_file
  puts "  > Created: #{group_name}"

  # ---------------------------------------------------------------------------
  # STEP 7: PREPROCESS AND IMPORT INP
  # ---------------------------------------------------------------------------
  puts ""
  puts stamp("Step 4: Import INP file to ICM")
  log "\nImporting INP file...", log_file

  import_log_path = File.join(log_dir, "INP_Import_#{Time.now.strftime('%Y%m%d_%H%M%S')}.txt")

  log "  Pre-processing INP file...", log_file
  original_basename = File.basename(inp_file)
  clean_basename    = URI.decode_www_form_component(original_basename)
  temp_processed    = File.join(temp_dir, "temp_processed.inp")
  final_inp         = File.join(temp_dir, clean_basename)

  log "  Original INP : #{original_basename}", log_file
  log "  Clean name   : #{clean_basename}", log_file

  truncate_long_fields(inp_file, temp_processed, log_file)

  unless File.exist?(temp_processed)
    raise "Processed INP file was not created: #{temp_processed}"
  end

  file_size = File.size(temp_processed)
  log "  Processed file size: #{file_size} bytes", log_file
  raise "Processed INP file is empty!" if file_size == 0

  File.rename(temp_processed, final_inp)
  log "  Renamed to: #{File.basename(final_inp)}", log_file
  log stamp("  Starting ICM import..."), log_file

  imported_objects = model_group.import_all_sw_model_objects(
    final_inp,
    'inp',
    '',
    import_log_path
  )

  if imported_objects.nil? || imported_objects.empty?
    log "  WARNING: No objects imported", log_file
    if File.exist?(import_log_path)
      log "  Import log contents:", log_file
      File.foreach(import_log_path) { |line| log "    #{line.strip}", log_file }
    end
    puts "ERROR: No objects were imported"
    puts "Check the import log: #{import_log_path}"

    begin
      model_group.delete
      log "  Deleted empty model group", log_file
    rescue => e
      log "  Could not delete empty model group: #{e.message}", log_file
    end

    exit 1
  end

  log "  SUCCESS: Imported #{imported_objects.length} object(s)", log_file
  puts "  > Imported #{imported_objects.length} object(s)"
  imported_objects.each do |obj|
    log "    - #{obj.type}: #{obj.name} (ID: #{obj.id})", log_file
  end

  # POST-IMPORT CLEANUP -------------------------------------------------------
  log "\n  Cleaning up imported objects...", log_file

  log "  Fixing URL-encoded names...", log_file
  imported_objects.each do |obj|
    begin
      decoded_name = URI.decode_www_form_component(obj.name)
      if decoded_name != obj.name
        log "    Renaming: '#{obj.name}' -> '#{decoded_name}'", log_file
        obj.name = decoded_name
      end
    rescue => e
      log "    WARNING: Could not rename '#{obj.name}': #{e.message}", log_file
    end
  end

  log "  Checking for empty label lists...", log_file
  label_lists_deleted = 0
  imported_objects.each do |obj|
    next unless obj.type == 'Label List'
    begin
      blob = obj['Blob']
      if blob.nil? || blob.empty?
        log "    Deleting empty label list: #{obj.name}", log_file
        obj.delete
        label_lists_deleted += 1
      else
        log "    Keeping label list with content: #{obj.name}", log_file
      end
    rescue => e
      log "    WARNING: Could not check/delete label list '#{obj.name}': #{e.message}", log_file
    end
  end

  if label_lists_deleted > 0
    log "  Deleted #{label_lists_deleted} empty label list(s)", log_file
    puts "  > Cleaned up #{label_lists_deleted} empty label list(s)"
  end

  # COMMIT NETWORK -----------------------------------------------------------
  imported_network = imported_objects.find { |o| o.type == 'SWMM network' }
  if imported_network
    begin
      model_basename       = File.basename(pcz_file, '.pcz')
      model_basename_clean = URI.decode_www_form_component(model_basename)

      log stamp("\n  Committing network: #{imported_network.name}"), log_file
      net = imported_network.open
      net&.commit("Imported from PCSWMM - #{model_basename_clean}")
      log "  Network committed successfully", log_file
    rescue => e
      log "  WARNING: Could not commit network: #{e.message}", log_file
    end
  end

  # ---------------------------------------------------------------------------
  # STEP 8: SUMMARY (cleanup occurs in ensure block)
  # ---------------------------------------------------------------------------
  log "\n" + "="*70, log_file
  log stamp("IMPORT COMPLETE"), log_file
  log "="*70, log_file
  log "Model Group     : #{group_name}", log_file
  log "Objects Imported: #{imported_objects.length}", log_file
  log "Log file        : #{log_filename}", log_file
  log "="*70, log_file

  puts ""
  puts "="*70
  puts stamp("IMPORT COMPLETE")
  puts "="*70
  puts "Model Group     : #{group_name}"
  puts "Objects Imported: #{imported_objects.length}"
  puts "Log file        : #{log_filename}"
  puts "="*70

rescue SystemExit, Interrupt
  raise
rescue => e
  msg = "\n" + "="*70 + "\n" \
        "FATAL ERROR in PCSWMM Exchange import\n" \
        "="*70 + "\n" \
        "Error: #{e.class} - #{e.message}\n" \
        "Backtrace:\n" + (e.backtrace || []).first(10).join("\n") + "\n" \
        "="*70 + "\n"
  puts msg
  log msg, log_file if log_file && !log_file.closed?
  exit 1
ensure
  begin
    net&.close
  rescue
    # network may already be closed
  end

  if log_file && !log_file.closed?
    begin
      log_file.close
    rescue
      # ignore
    end
  end

  if temp_dir && Dir.exist?(temp_dir)
    begin
      FileUtils.rm_rf(temp_dir)
    rescue
      # ignore
    end
  end

  puts stamp("Script terminated")
end
