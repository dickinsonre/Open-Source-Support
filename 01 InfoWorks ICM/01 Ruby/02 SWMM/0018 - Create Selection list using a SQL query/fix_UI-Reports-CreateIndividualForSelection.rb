# frozen_string_literal: true

# =============================================================================
# fix_UI-Reports-CreateIndividualForSelection.rb
# -----------------------------------------------------------------------------
# Purpose : Generate an individual Word/HTML report for every selected row
#           in the configured CAMS table (default cams_manhole_survey).
# Inputs  : Current open network (UI). TABLES constant defines which report
#           templates to use. Output folder is hard-coded under c:\\temp.
# Outputs : One .doc per row object on disk.
# UI / EX : UI script (uses current_network and generate_report).
# Hardening:
#   - frozen_string_literal
#   - Header block, begin/rescue/ensure
#   - Validates network not nil
#   - Validates row collection non-empty
#   - Ensures output directory exists (FileUtils.mkdir_p)
#   - Per-row rescue so a single failure does not abort the run
#   - Timestamped progress logging and per-table count
#   - Preserves original behaviour (Word reports under c:\\temp)
# =============================================================================

require 'fileutils'

def ts
  Time.now.strftime('%Y-%m-%d %H:%M:%S')
end

OUTPUT_DIR = 'c:\\temp'
TABLES = [['cams_manhole_survey', nil]].freeze
# Available reports:
# [['cams_manhole',nil],['cams_manhole_survey',nil],
#  ['cams_cctv_survey','MSCC'],['cams_cctv_survey','PACP'],
#  ['cams_cctv_survey',nil],['cams_pipe_clean',nil],
#  ['cams_pipe_repair',nil],['cams_manhole_repair',nil],
#  ['cams_fog_inspection',nil]]

begin
  puts "[#{ts}] Starting Create Individual Reports for Selection."

  net = WSApplication.current_network
  raise 'No current network is open.' if net.nil?

  FileUtils.mkdir_p(OUTPUT_DIR)

  total = 0
  TABLES.each do |t|
    table, suffix_in = t
    puts "[#{ts}] Processing table '#{table}' suffix='#{suffix_in.inspect}'"

    rows = net.row_objects_selection(table)
    if rows.nil? || rows.empty?
      puts "[#{ts}] WARNING: no selected rows for '#{table}'. Skipping."
      next
    end

    rows.each do |ro|
      begin
        net.clear_selection
        ro.selected = true

        suffix = suffix_in.nil? ? '' : "#{suffix_in}_"
        prefix = "#{OUTPUT_DIR}\\Report_#{table}_#{suffix}_#{ro.id}"
        out    = "#{prefix}.doc"

        net.generate_report(table, suffix_in, ro.id, out)
        # net.generate_report(table, suffix_in, ro.id, prefix + '.html')

        total += 1
      rescue StandardError => row_e
        puts "[#{ts}] ERROR generating report for #{table}/#{ro.id}: #{row_e.message}"
      end
    end
  end

  puts "[#{ts}] Reports exported (#{total}) to #{OUTPUT_DIR}."
  begin
    WSApplication.message_box "Reports Exported (#{total})", 'OK', 'Information', false
  rescue StandardError
    # message_box may not be available in all contexts; ignore.
  end
rescue StandardError => e
  puts "[#{ts}] FATAL: #{e.message}"
  puts e.backtrace&.first(5)&.join("\n")
ensure
  puts "[#{ts}] Script finished."
end
