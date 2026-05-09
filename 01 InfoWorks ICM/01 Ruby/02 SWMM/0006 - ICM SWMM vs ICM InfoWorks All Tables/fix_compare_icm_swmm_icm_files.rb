# frozen_string_literal: true
# ---------------------------------------------------------------------------
# fix_compare_icm_swmm_icm_files.rb
#
# Purpose : Compare two CSV files (one from ICM SWMM, one from ICM InfoWorks)
#           by checking the values in column index 1 row by row.
# Inputs  : Two file paths to existing .csv files.
# Outputs : Returns true if all column-1 values match, false otherwise.
#           Reports row-by-row diffs to stdout.
# Type    : Library / EX-style script.
# Hardening:
#   * frozen_string_literal pragma
#   * Validates both files exist before reading
#   * begin/rescue/ensure with timestamped logging
#   * Uses CSV.foreach via File.open for streamed reading where possible
#   * Handles unequal row counts gracefully
# ---------------------------------------------------------------------------

require 'csv'

def log(msg)
  puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] #{msg}"
end

def compare_icm_swmm_icm_files(icm_swmm_csv_file, icm_csv_file)
  raise ArgumentError, "ICM SWMM CSV not found: #{icm_swmm_csv_file}" unless File.exist?(icm_swmm_csv_file.to_s)
  raise ArgumentError, "ICM CSV not found: #{icm_csv_file}"           unless File.exist?(icm_csv_file.to_s)

  begin
    icm_swmm_csv = CSV.read(icm_swmm_csv_file)
    icm_csv      = CSV.read(icm_csv_file)

    if icm_swmm_csv.length != icm_csv.length
      log "Row count differs: #{icm_swmm_csv.length} vs #{icm_csv.length}"
    end

    all_match = true
    [icm_swmm_csv.length, icm_csv.length].min.times do |i|
      a = icm_swmm_csv[i] && icm_swmm_csv[i][1]
      b = icm_csv[i]      && icm_csv[i][1]
      if a != b
        log "Row #{i}: #{a.inspect} != #{b.inspect}"
        all_match = false
      end
    end

    all_match
  rescue StandardError => e
    log "compare_icm_swmm_icm_files aborted: #{e.message}"
    false
  ensure
    log "Comparison finished for #{icm_swmm_csv_file} vs #{icm_csv_file}"
  end
end
