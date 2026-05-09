# frozen_string_literal: true

# =============================================================================
# fix_UI-Reports-CreateIndividualForSelection_folder.rb
# -----------------------------------------------------------------------------
# Purpose : Generate an individual Word/HTML report for every selected row,
#           prompting the user for the destination folder.
# Inputs  : Current open network. User-picked output folder (folder dialog).
# Outputs : One .doc per row object on disk.
# UI / EX : UI script (uses current_network and folder_dialog).
# Hardening:
#   - frozen_string_literal
#   - Header block, begin/rescue/ensure
#   - Validates network not nil
#   - Validates folder dialog was not cancelled
#   - Ensures output directory exists (FileUtils.mkdir_p)
#   - Per-row rescue so a single failure does not abort the run
#   - Timestamped progress logging
#   - Preserves original behaviour
# =============================================================================

require 'fileutils'

def ts
  Time.now.strftime('%Y-%m-%d %H:%M:%S')
end

TABLES = [['cams_cctv_survey', 'MSCC']].freeze

begin
  puts "[#{ts}] Starting Create Individual Reports (folder picker)."

  net = WSApplication.current_network
  raise 'No current network is open.' if net.nil?

  folder = WSApplication.folder_dialog('Select an Export Location', true)
  if folder.nil? || folder.to_s.strip.empty?
    raise 'Folder selection was cancelled - nothing to do.'
  end
  FileUtils.mkdir_p(folder)
  puts "[#{ts}] Output folder: #{folder}"

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
        prefix = "#{folder}\\#{table}_#{suffix}#{ro.id}"
        net.generate_report(table, suffix_in, ro.id, prefix + '.doc')
        # net.generate_report(table, suffix_in, ro.id, prefix + '.html')
        total += 1
      rescue StandardError => row_e
        puts "[#{ts}] ERROR for #{table}/#{ro.id}: #{row_e.message}"
      end
    end
  end

  puts "[#{ts}] Reports exported (#{total}) to #{folder}."
  begin
    WSApplication.message_box "Reports exported to #{folder} (#{total})", 'OK', 'Information', false
  rescue StandardError
    # ignore if not supported
  end
rescue StandardError => e
  puts "[#{ts}] FATAL: #{e.message}"
  puts e.backtrace&.first(5)&.join("\n")
ensure
  puts "[#{ts}] Script finished."
end
