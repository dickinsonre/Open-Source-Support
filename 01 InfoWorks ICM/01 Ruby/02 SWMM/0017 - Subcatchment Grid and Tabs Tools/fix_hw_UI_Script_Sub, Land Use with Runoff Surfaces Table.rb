# frozen_string_literal: true
# =============================================================================
# fix_hw_UI_Script_Sub, Land Use with Runoff Surfaces Table.rb
# =============================================================================
# Purpose:
#   Hardened report combining the Land Use + Runoff Surfaces table with a
#   Subcatchment Grid (areas absolute and percent for slots 1..12).
#
# Inputs:  Current network with hw_land_use, hw_runoff_surface, hw_subcatchment.
# Outputs: Console tables.
# UI vs Exchange: UI script.
#
# Hardening notes:
#   - frozen_string_literal, timestamped logging
#   - begin/rescue/ensure; per-row rescue; nil-safe
# =============================================================================

def ts_log(msg)
  puts "[#{Time.now.strftime('%H:%M:%S')}] #{msg}"
end

begin
  ts_log "Starting Sub + Land Use + Runoff Surfaces report"

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
      ts_log "Skip land_use #{land_use&.land_use_id}: #{e.message}"
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

  subcatchment_variables = []
  cn.row_objects('hw_subcatchment').each do |sub|
    next if sub.nil?
    begin
      h = {
        'Subcatchment ID' => sub.subcatchment_id,
        'Land use ID' => sub.land_use_id,
        'Total area' => sub.total_area,
        'Contributed_area' => sub.contributing_area,
        'Area measurement type' => sub.area_measurement_type
      }
      (1..12).each do |i|
        h["Runoff area #{i} absolute"] = sub.send("area_absolute_#{i}")
      end
      (1..12).each do |i|
        h["Runoff area #{i} (%)"] = sub.send("area_percent_#{i}")
      end
      subcatchment_variables << h
    rescue => e
      ts_log "Skip subcatchment #{sub&.subcatchment_id}: #{e.message}"
    end
  end

  if subcatchment_variables.any?
    puts subcatchment_variables.first.keys.each_with_index.map { |key, index|
      key = key.gsub('Runoff ', '').gsub('absolute', '').gsub('area', 'A')
      index < 1 ? key[0, 20].ljust(20) : key[0, 8].ljust(8)
    }.join(", ")
    subcatchment_variables.each do |variables|
      row = variables.values.each_with_index.map { |v, i| i < 1 ? v.to_s[0, 20].ljust(20) : v.to_s[0, 8].ljust(8) }.join(", ")
      puts row
    end
  end

rescue => e
  ts_log "FATAL: #{e.class}: #{e.message}"
  puts e.backtrace.first(5).join("\n") if e.backtrace
ensure
  ts_log "Sub + Land Use + Runoff Surfaces finished"
end
