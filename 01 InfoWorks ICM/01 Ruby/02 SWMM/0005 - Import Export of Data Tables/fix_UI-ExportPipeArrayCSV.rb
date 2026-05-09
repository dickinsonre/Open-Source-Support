# frozen_string_literal: true
# ---------------------------------------------------------------------------
# fix_UI-ExportPipeArrayCSV.rb
#
# Purpose : Export the point_array for selected cams_pipe rows to CSV.
# Inputs  : Active current_network with a selection on cams_pipe.
# Outputs : CSV file at OUT_PATH (us_node_id, ds_node_id, link_suffix,
#           point_array).
# Type    : UI script.
# Hardening:
#   * frozen_string_literal pragma
#   * Validates current_network and that selection is non-empty
#   * CSV.open block ensures file is closed
#   * Nil-safe attribute access
#   * Timestamped logging
# ---------------------------------------------------------------------------

require 'csv'
require 'fileutils'

OUT_PATH = 'c:\\temp\\pipes.csv'

def log(msg); puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] #{msg}"; end

begin
  net = WSApplication.current_network
  raise 'No current network is open.' if net.nil?

  pipes = net.row_objects_selection('cams_pipe')
  raise 'No pipes are selected.' if pipes.nil? || pipes.to_a.empty?

  FileUtils.mkdir_p(File.dirname(OUT_PATH)) unless Dir.exist?(File.dirname(OUT_PATH))

  count = 0
  CSV.open(OUT_PATH, 'wb') do |csv|
    pipes.each do |s|
      next if s.nil?
      if s.point_array.nil?
        puts "#{s.us_node_id}.#{s.ds_node_id}.#{s.link_suffix}"
        csv << [s.us_node_id.to_s, s.ds_node_id.to_s, s.link_suffix.to_s]
      else
        puts "#{s.us_node_id}.#{s.ds_node_id}.#{s.link_suffix} #{s.point_array}"
        csv << [s.us_node_id.to_s, s.ds_node_id.to_s, s.link_suffix.to_s, s.point_array.to_s]
      end
      count += 1
    end
  end
  log "Wrote #{count} pipe rows to #{OUT_PATH}"
rescue StandardError => e
  log "Aborted: #{e.message}"
ensure
  log 'fix_UI-ExportPipeArrayCSV.rb finished.'
end
