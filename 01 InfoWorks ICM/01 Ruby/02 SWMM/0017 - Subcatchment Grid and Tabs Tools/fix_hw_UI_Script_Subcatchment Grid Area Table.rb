# frozen_string_literal: true
# =============================================================================
# fix_hw_UI_Script_Subcatchment Grid Area Table.rb
# =============================================================================
# Purpose:
#   Hardened report that prints the hw_subcatchment grid (ID, Land Use,
#   Total Area, contributing area, measurement type) plus area_absolute_N
#   and area_percent_N for slots 1..12.
#
# Inputs:  Current network with hw_subcatchment rows.
# Outputs: Console table.
# UI vs Exchange: UI script.
#
# Hardening notes:
#   - frozen_string_literal, timestamped logging
#   - begin/rescue/ensure; per-row rescue
# =============================================================================

def ts_log(msg)
  puts "[#{Time.now.strftime('%H:%M:%S')}] #{msg}"
end

begin
  ts_log "Starting Subcatchment Grid Area Table"
  cn = WSApplication.current_network
  raise "No current network." if cn.nil?

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
      (1..12).each { |i| h["Runoff area #{i} absolute"] = sub.send("area_absolute_#{i}") }
      (1..12).each { |i| h["Runoff area #{i} (%)"]     = sub.send("area_percent_#{i}") }
      subcatchment_variables << h
    rescue => e
      ts_log "Skip subcatchment #{sub&.subcatchment_id}: #{e.message}"
    end
  end

  if subcatchment_variables.empty?
    ts_log "No subcatchments to print."
    return
  end

  puts subcatchment_variables.first.keys.each_with_index.map { |key, index|
    key = key.gsub('Runoff ', '').gsub('absolute', '').gsub('area', 'A')
    index < 1 ? key[0, 20].ljust(20) : key[0, 8].ljust(8)
  }.join(", ")
  subcatchment_variables.each do |variables|
    row = variables.values.each_with_index.map { |v, i| i < 1 ? v.to_s[0, 20].ljust(20) : v.to_s[0, 8].ljust(8) }.join(", ")
    puts row
  end

rescue => e
  ts_log "FATAL: #{e.class}: #{e.message}"
  puts e.backtrace.first(5).join("\n") if e.backtrace
ensure
  ts_log "Subcatchment Grid Area Table finished"
end
