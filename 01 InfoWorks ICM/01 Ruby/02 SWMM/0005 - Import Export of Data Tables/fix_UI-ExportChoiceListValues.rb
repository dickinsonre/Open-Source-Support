# frozen_string_literal: true
# ---------------------------------------------------------------------------
# fix_UI-ExportChoiceListValues.rb
#
# Purpose : Export choice-list values (codes + descriptions) for a given
#           field on a given table to CSV.
# Inputs  : Active current_network; TBL/COL constants below.
# Outputs : CSV file at OUT_PATH (table, field, code, description per row).
# Type    : UI script.
# Hardening:
#   * frozen_string_literal pragma
#   * Validates current_network not nil
#   * CSV.open block ensures file is closed
#   * Nil-safety on field_choices/field_choice_descriptions
#   * Timestamped logging
# ---------------------------------------------------------------------------

require 'csv'
require 'fileutils'

OUT_PATH = 'c:\\temp\\choices.csv'
TBL      = 'cams_cctv_survey'
COL      = 'category_code'

def log(msg); puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] #{msg}"; end

begin
  nw = WSApplication.current_network
  raise 'No current network is open.' if nw.nil?

  FileUtils.mkdir_p(File.dirname(OUT_PATH)) unless Dir.exist?(File.dirname(OUT_PATH))

  fc = nw.field_choices(TBL, COL)
  fd = nw.field_choice_descriptions(TBL, COL)
  raise "No choices/descriptions returned for #{TBL}.#{COL}." if fc.nil? || fd.nil?

  CSV.open(OUT_PATH, 'wb') do |csv|
    fc.each_with_index do |value, i|
      desc = fd[i]
      puts %("#{TBL}","#{COL}","#{value}","#{desc}")
      csv << [TBL.to_s, COL.to_s, value.to_s, desc.to_s]
    end
  end
  log "Wrote #{fc.size} rows to #{OUT_PATH}"
rescue StandardError => e
  log "Aborted: #{e.message}"
ensure
  log 'fix_UI-ExportChoiceListValues.rb finished.'
end
