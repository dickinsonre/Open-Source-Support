# frozen_string_literal: true
# =============================================================================
# fix_hw_UI_Script_Runoff Surface Tables.rb
# =============================================================================
# Purpose:
#   Hardened report that lists every hw_runoff_surface with its full set of
#   routing/loss/infiltration parameters in a fixed-width text table, then
#   shows a configuration prompt mirroring those fields.
#
# Inputs:  Current network with hw_runoff_surface rows.
# Outputs: Console table; prompt is purely informational.
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
  ts_log "Starting Runoff Surface Tables"
  cn = WSApplication.current_network
  raise "No current network." if cn.nil?

  runoff_surface_variables = []
  cn.row_objects('hw_runoff_surface').each do |ro|
    next if ro.nil?
    begin
      runoff_surface_variables << {
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
        'Fixed runoff coefficient' => ro.runoff_coefficient,
        'Minimum runoff' => ro.minimum_runoff,
        'Maximum runoff' => ro.maximum_runoff,
        'RAFTS adapt factor' => ro.rafts_adapt_factor,
        "Equivalent Manning's n" => ro.equivalent_roughness,
        'Wal. proc. distribution' => ro.runoff_distribution_factor,
        'New UK depth' => ro.moisture_depth_parameter,
        'SCS depth' => ro.storage_depth,
        'Initial infiltration' => ro.initial_infiltration,
        'Limiting infiltration' => ro.limiting_infiltration,
        'Decay factor' => ro.decay_factor,
        'Horton drying time' => ro.drying_time,
        'Horton max infiltration volume' => ro.max_infiltration_volume,
        'Recovery factor' => ro.recovery_factor,
        'Number of reservoirs' => ro.number_of_reservoirs,
        'Depression Loss' => ro.depression_loss,
        'Green-Ampt suction' => ro.average_capillary_suction,
        'Green-Ampt conductivity' => ro.saturated_hydraulic_conductivity,
        'Green-Ampt deficit' => ro.initial_moisture_deficit,
        'Horner alpha' => ro.halpha,
        'Horner beta' => ro.hbeta,
        'Horner recovery (min)' => ro.hrecovery,
        'Initial loss porosity' => ro.initial_loss_porosity,
        'Infiltration loss coefficient' => ro.infiltration_coeff,
        'Maximum deficit' => ro.maximum_deficit,
        'Effective impermeability' => ro.effective_impermeability,
        'Precipitation decay coefficient' => ro.precipitation_decay,
        'Power coefficient for PI' => ro.power_coeff_paved,
        'Storage depth' => ro.storage_depth_paved,
        'Wetness decay for NAPI' => ro.napi_decay_coeff,
        'Power coefficient' => ro.power_coeff_pervious,
        'Storage depth ' => ro.storage_depth_pervious,
        'Minimum NAPI' => ro.minimum_napi,
        'Saturated rainfall' => ro.saturated_rainfall
      }
    rescue => e
      ts_log "Skip surface #{ro&.runoff_index}: #{e.message}"
    end
  end

  if runoff_surface_variables.empty?
    ts_log "No runoff surfaces to print."
    return
  end

  puts runoff_surface_variables.first.keys.each_with_index.map { |k, i| i == 5 ? k[0, 30].ljust(30) : k[0, 15].ljust(15) }.join(", ")
  runoff_surface_variables.each do |variables|
    row = variables.values.each_with_index.map { |v, i| i == 5 ? v.to_s[0, 20].ljust(20) : v.to_s[0, 15].ljust(15) }.join(", ")
    puts row
  end

  begin
    WSApplication.prompt("Runoff Surface Fields in the Subcatchment Grid",
      [
        ['Runoff surface ID', 'String', ''],
        ['Description', 'String', ''],
        ['Runoff routing type', 'String', ''],
        ['Runoff routing value', 'String', ''],
        ['Runoff volume type', 'String', ''],
        ['Surface type', 'String', ''],
        ['Ground slope', 'String', ''],
        ['Initial loss type', 'String', ''],
        ['Initial loss value', 'String', ''],
        ['Initial abstraction factor', 'String', ''],
        ['Routing model', 'String', ''],
        ['Fixed runoff coefficient', 'String', '']
      ], false)
  rescue => e
    ts_log "Prompt failed (non-fatal): #{e.message}"
  end

rescue => e
  ts_log "FATAL: #{e.class}: #{e.message}"
  puts e.backtrace.first(5).join("\n") if e.backtrace
ensure
  ts_log "Runoff Surface Tables finished"
end
