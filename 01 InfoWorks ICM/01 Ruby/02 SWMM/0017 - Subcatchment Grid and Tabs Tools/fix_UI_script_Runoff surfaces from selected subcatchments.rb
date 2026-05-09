# frozen_string_literal: true
# =============================================================================
# fix_UI_script_Runoff surfaces from selected subcatchments.rb
# =============================================================================
# Purpose:
#   Hardened helper that walks the runoff-surface -> land-use -> subcatchment
#   hierarchy. Starting from selected hw_runoff_surface rows it (a) selects
#   every hw_land_use that references those surfaces in any runoff_index_N
#   column, and (b) selects every hw_subcatchment whose land_use_id matches.
#
# Inputs:
#   - Current network with hw_runoff_surface rows already selected
#
# Outputs:
#   - Updates `selected` flag on hw_land_use and hw_subcatchment rows
#
# UI vs Exchange: UI script.
#
# Hardening notes:
#   - frozen_string_literal, timestamped logging
#   - begin/rescue/ensure top-level
#   - per-row rescue, nil-safe value access
# =============================================================================

def ts_log(msg)
  puts "[#{Time.now.strftime('%H:%M:%S')}] #{msg}"
end

begin
  ts_log "Starting select-land-use-and-subs-from-runoff-surfaces"

  net = WSApplication.current_network
  raise "No current network." if net.nil?

  selected_runoff_surfaces = {}
  net.row_objects_selection('hw_runoff_surface').each do |rs|
    next if rs.nil?
    selected_runoff_surfaces[rs.id] = 0
  end
  ts_log "Selected runoff surfaces: #{selected_runoff_surfaces.size}"

  selected_land_uses = {}
  net.row_objects('hw_land_use').each do |lu|
    next if lu.nil?
    begin
      (1..10).each do |i|
        rs = lu["runoff_index_#{i}"]
        next if rs.nil?
        if selected_runoff_surfaces.key?(rs)
          selected_land_uses[lu.id] = 0
          lu.selected = true
          break
        end
      end
    rescue => e
      ts_log "Skip land_use #{lu&.id}: #{e.message}"
    end
  end
  ts_log "Selected land uses: #{selected_land_uses.size}"

  count = 0
  net.row_objects('hw_subcatchment').each do |s|
    next if s.nil?
    begin
      if selected_land_uses.key?(s.land_use_id)
        s.selected = true
        count += 1
      end
    rescue => e
      ts_log "Skip subcatchment #{s&.subcatchment_id}: #{e.message}"
    end
  end
  ts_log "Selected subcatchments: #{count}"

rescue => e
  ts_log "FATAL: #{e.class}: #{e.message}"
  puts e.backtrace.first(5).join("\n") if e.backtrace
ensure
  ts_log "Done."
end
