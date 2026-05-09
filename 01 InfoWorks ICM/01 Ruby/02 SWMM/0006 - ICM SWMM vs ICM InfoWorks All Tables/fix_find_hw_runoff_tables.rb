# frozen_string_literal: true
# ---------------------------------------------------------------------------
# fix_find_hw_runoff_tables.rb
#
# Purpose : Given a user selection on hw_runoff_surface, find the matching
#           hw_land_use rows (by runoff_index_1..12) and then mark all
#           hw_subcatchment rows with that land_use_id as selected.
# Inputs  : Active InfoWorks current_network with a selection on
#           hw_runoff_surface.
# Outputs : Updates selection state on hw_land_use and hw_subcatchment.
#           Prints summary counts.
# Type    : UI script.
# Hardening:
#   * frozen_string_literal pragma
#   * Validates current_network not nil
#   * Validates non-empty selection on hw_runoff_surface
#   * begin/rescue/ensure around main logic
#   * Nil-safe attribute access
#   * Timestamped logging
# ---------------------------------------------------------------------------

require 'set'

def log(msg)
  puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] #{msg}"
end

begin
  net = WSApplication.current_network
  raise 'No current network is open.' if net.nil?

  selected_runoff_surfaces = Set.new
  net.row_objects_selection('hw_runoff_surface').each do |rs|
    next if rs.nil?
    selected_runoff_surfaces << rs.id.to_s
  end

  if selected_runoff_surfaces.empty?
    log 'No hw_runoff_surface rows are selected. Select some and rerun.'
    raise 'Empty hw_runoff_surface selection.'
  end

  log "Selected runoff surfaces: #{selected_runoff_surfaces.size}"

  selected_land_uses = Set.new
  net.row_objects('hw_land_use').each do |lu|
    next if lu.nil?
    has_match = (1..12).any? do |i|
      val = lu["runoff_index_#{i}"]
      val && selected_runoff_surfaces.include?(val.to_s)
    end
    if has_match
      selected_land_uses << lu.id.to_s
      lu.selected = true
    end
  end

  net.row_objects('hw_subcatchment').each do |s|
    next if s.nil?
    s.selected = true if s.land_use_id && selected_land_uses.include?(s.land_use_id.to_s)
  end

  all_subcatchments      = net.row_objects('hw_subcatchment')
  selected_subcatchments = all_subcatchments.select(&:selected)
  all_land_uses          = net.row_objects('hw_land_use')
  all_runoff_surfaces    = net.row_objects('hw_runoff_surface')

  puts "Total Subcatchments: #{all_subcatchments.size}"
  puts "Selected Subcatchments: #{selected_subcatchments.size}"
  puts "Total Land Uses: #{all_land_uses.size}"
  puts "Selected Land Uses: #{selected_land_uses.size}"
  puts "Selected Land Use IDs: #{selected_land_uses.to_a.join(', ')}"
  puts "Total Runoff Surfaces: #{all_runoff_surfaces.size}"
rescue StandardError => e
  log "Aborted: #{e.message}"
  log e.backtrace.first(5).join("\n") if e.backtrace
ensure
  log 'fix_find_hw_runoff_tables.rb finished.'
end
