# frozen_string_literal: true
# =============================================================================
# fix_hw_UI_Script_InfoWorks Land Use Tables.rb
# =============================================================================
# Purpose:
#   Hardened report that lists every hw_land_use row with its runoff-index /
#   default-area columns from slot 1 to 12 in a fixed-width text table.
#
# Inputs:  Current network with hw_land_use rows.
# Outputs: Console table.
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
  ts_log "Starting Land Use Tables"
  cn = WSApplication.current_network
  raise "No current network." if cn.nil?

  land_use_variables = []
  cn.row_objects('hw_land_use').each do |ro|
    next if ro.nil?
    begin
      h = {
        'Land use ID' => ro.land_use_id,
        'Population density' => ro.population_density,
        'Wastewater profile' => ro.wastewater_profile,
        'Connectivity (%)' => ro.connectivity,
        'Pollution index' => ro.pollution_index,
        'Description' => ro.land_use_description
      }
      (1..12).each do |i|
        h["Runoff surface #{i}"]    = ro.send("runoff_index_#{i}")
        h["Default area #{i} (%)"] = ro.send("p_area_#{i}")
      end
      land_use_variables << h
    rescue => e
      ts_log "Skip #{ro&.land_use_id}: #{e.message}"
    end
  end

  if land_use_variables.empty?
    ts_log "No land uses to print."
    return
  end

  puts land_use_variables.first.keys.each_with_index.map { |k, i| i == 5 ? k[0, 40].ljust(40) : k[0, 20].ljust(20) }.join(", ")
  land_use_variables.each do |variables|
    row = variables.values.each_with_index.map { |v, i| i == 5 ? v.to_s[0, 40].ljust(40) : v.to_s[0, 20].ljust(20) }.join(", ")
    puts row
  end

rescue => e
  ts_log "FATAL: #{e.class}: #{e.message}"
  puts e.backtrace.first(5).join("\n") if e.backtrace
ensure
  ts_log "Land Use Tables finished"
end
