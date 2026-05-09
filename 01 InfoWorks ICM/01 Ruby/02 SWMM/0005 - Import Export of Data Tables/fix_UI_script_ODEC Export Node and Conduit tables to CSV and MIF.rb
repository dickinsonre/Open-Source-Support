# frozen_string_literal: true
# ---------------------------------------------------------------------------
# fix_UI_script_ODEC Export Node and Conduit tables to CSV and MIF.rb
#
# Purpose : Use odec_export_ex to export Node and Conduit tables of the
#           current network to CSV and MIF using a config file mapping.
# Inputs  : Working directory containing ICMFieldMapping.cfg.
# Outputs : One CSV/MIF per table per format; error log file in cwd.
# Type    : UI script.
# Hardening:
#   * frozen_string_literal pragma
#   * Validates current_network not nil
#   * Validates working directory and config file exist
#   * begin/rescue/ensure with timestamped logging
# ---------------------------------------------------------------------------

require 'date'

WORK_DIR = 'C:\\Users\\dickinre\\Documents\\Open-Source-Support-main\\01 InfoWorks ICM\\ICM SWMM Ruby\\0012 - ODEC Export Node and Conduit tables to CSV and MIF'
CFG_FILE = './ICMFieldMapping.cfg'

def log(msg); puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] #{msg}"; end

begin
  raise "Working directory does not exist: #{WORK_DIR}" unless Dir.exist?(WORK_DIR)
  Dir.chdir(WORK_DIR)
  raise "Config file not found: #{CFG_FILE}" unless File.exist?(CFG_FILE)

  net = WSApplication.current_network
  raise 'No current network is open.' if net.nil?

  mo = net.model_object
  export_date = DateTime.now.strftime('%Y%d%m%H%S')

  options = { 'Error File' => '.\\ICMExportErrors.txt' }

  outputs = %w[CSV MIF]
  tables  = %w[Node Conduit]

  outputs.each do |output|
    tables.each do |table|
      log "#{table} - #{output} export commenced: #{DateTime.now.to_time}"
      file_name = "#{export_date} #{mo.name} - #{table}"
      ext = output == 'CSV' ? '.csv' : ''
      net.odec_export_ex(output, CFG_FILE, options, table, file_name + ext)
      log "=> Exported file: \"#{Dir.getwd}/#{file_name}\""
      log "#{table} - #{output} export complete: #{DateTime.now.to_time}"
    end
  end
rescue StandardError => e
  log "Aborted: #{e.message}"
ensure
  log 'fix_UI_script_ODEC Export Node and Conduit tables to CSV and MIF.rb finished.'
end
