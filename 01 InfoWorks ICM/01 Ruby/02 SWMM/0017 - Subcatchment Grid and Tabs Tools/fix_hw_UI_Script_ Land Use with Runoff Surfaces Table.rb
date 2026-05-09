# frozen_string_literal: true
# =============================================================================
# fix_hw_UI_Script_ Land Use with Runoff Surfaces Table.rb
# =============================================================================
# Purpose:
#   Hardened report that walks each hw_land_use, prints its core fields and
#   then prints, for each runoff_index_1..12 slot, the matching
#   hw_runoff_surface fields (slope, routing type, loss, etc.).
#
# Inputs:
#   - Current network with hw_land_use and hw_runoff_surface rows
#
# Outputs:
#   - Console table (Land Use rows interleaved with their Runoff Surface rows)
#
# UI vs Exchange: UI script.
#
# Hardening notes:
#   - frozen_string_literal, timestamped logging
#   - begin/rescue/ensure top-level + per-row rescue
#   - nil-safe field access via &.
# =============================================================================

def ts_log(msg)
  puts "[#{Time.now.strftime('%H:%M:%S')}] #{msg}"
end

begin
  ts_log "Starting Land Use with Runoff Surfaces Table"

  cn = WSApplication.current_network
  raise "No current network." if cn.nil?

  combined_variables = []
  cn.row_objects('hw_land_use').each do |land_use|
    next if land_use.nil?
    begin
      lu_vars = {
        'Land use ID' => land_use.land_use_id,
        'Population density' => land_use.population_density,
        'Wastewater profile' => land_use.wastewater_profile,
        'Connectivity (%)' => land_use.connectivity,
        'Pollution index' => land_use.pollution_index,
        'Description' => land_use.land_use_description
      }
      (1..12).each do |i|
        lu_vars["Runoff surface ##{i}"]    = land_use.send("runoff_index_#{i}")
        lu_vars["Default area ##{i} (%)"] = land_use.send("p_area_#{i}")
      end
      combined_variables << lu_vars

      cn.row_objects('hw_runoff_surface').each do |ro|
        next if ro.nil?
        (1..12).each do |i|
          if ro.runoff_index == land_use.send("runoff_index_#{i}")
            combined_variables << {
              'Runoff surface ID' => ro.runoff_index,
              'Description' => ro.surface_description,
              'Runoff routing type' => ro.runoff_routing_type,
              'Runoff routing value' => ro.runoff_routing_value,
              'Runoff volume type' => ro.runoff_volume_type,
              'Surface type' => ro.surface_type,
              'Ground slope' => ro.ground_slope,
              'Initial loss type' => ro.initial_loss_type,
              'Initial loss value' => ro.initial_loss_value,
              'Initial abstraction factor' => ro.initial_abstraction_factor,
              'Routing model' => ro.routing_model,
              'Fixed runoff coefficient' => ro.runoff_coefficient
            }
          end
        end
      end
    rescue => e
      ts_log "Skip land use #{land_use&.land_use_id}: #{e.message}"
    end
  end

  combined_variables.each do |variables|
    row = variables.values.each_with_index.map { |v, i| i == 5 ? v.to_s[0, 30].ljust(30) : v.to_s[0, 10].ljust(10) }.join(", ")
    if variables.keys.first.start_with?('Land use')
      puts "Land Use       " + row
    elsif variables.keys.first.start_with?('Runoff surface')
      puts "Runoff Surface " + row
    else
      puts row
    end
  end

rescue => e
  ts_log "FATAL: #{e.class}: #{e.message}"
  puts e.backtrace.first(5).join("\n") if e.backtrace
ensure
  ts_log "Land Use with Runoff Surfaces Table finished"
end
