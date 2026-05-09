# frozen_string_literal: true
# ---------------------------------------------------------------------------
# fix_UI_script_Output CSV of calcs based on Subcatchment Data.rb
#
# Purpose : Walk all _subcatchments rows where selected==true, accumulate
#           foul/combined/other category sums of total_area, contributing
#           area, population, paved/roof/permeable areas and trade/base flow
#           to write a single summary row to a CSV chosen via file_dialog.
# Inputs  : Active current_network with selected subcatchments.
# Outputs : CSV chosen by user.
# Type    : UI script.
# Hardening:
#   * frozen_string_literal pragma
#   * Validates current_network not nil and dialog not cancelled
#   * File.open block ensures the CSV is closed
#   * Nil-safe attribute access via to_f and ||
#   * Timestamped logging
# ---------------------------------------------------------------------------

require 'csv'

def log(msg); puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] #{msg}"; end

begin
  net = WSApplication.current_network
  raise 'No current network is open.' if net.nil?

  csv_save_loc = WSApplication.file_dialog(false, 'csv', 'Comma Separated Variable File',
                                           'Drainage Capacity Factor Assessment', false, true)
  raise 'No output CSV chosen.' if csv_save_loc.nil? || csv_save_loc.to_s.empty?

  header = [
    'ID',
    'Total Subcatchment Area (ha)', 'Contributing Subcatchment Area (ha)',
    'Total Pavement Area (ha)', 'Total Roof Area (ha)', 'Total Permeable Area (ha)',
    'Population', 'Non Domentic Flow (l/s)', 'Infiltration (l/s)'
  ]

  totals = Hash.new(0.0)
  totals[:tradeflow] = 0.0
  totals[:baseflow]  = 0.0
  totals[:addfoulflow] = 0.0
  sccount = 0

  net.row_objects('_subcatchments').each do |sc|
    next if sc.nil?
    next unless sc.selected
    sccount += 1
    sys = sc.system_type ? sc.system_type.downcase : 'other'
    suffix = case sys
             when 'foul'     then 'f'
             when 'combined' then 'c'
             else 'o'
             end
    totals["totscarea_#{suffix}".to_sym] += sc.total_area.to_f         if sc.total_area
    totals["conscarea_#{suffix}".to_sym] += sc.contributing_area.to_f  if sc.contributing_area
    totals["popul_#{suffix}".to_sym]     += sc.population.to_f         if sc.population
    totals["pavearea_#{suffix}".to_sym]  += sc.area_absolute_1.to_f    if sc.area_absolute_1
    totals["roofarea_#{suffix}".to_sym]  += sc.area_absolute_2.to_f    if sc.area_absolute_2
    totals["permarea_#{suffix}".to_sym]  += sc.area_absolute_3.to_f    if sc.area_absolute_3
    totals[:addfoulflow]                 += sc.additional_foul_flow.to_f if sc.additional_foul_flow
    totals[:tradeflow]                   += sc.trade_flow.to_f         if sc.trade_flow
    totals[:baseflow]                    += sc.base_flow.to_f          if sc.base_flow
  end

  totscarea = totals[:totscarea_f] + totals[:totscarea_c] + totals[:totscarea_o]
  conscarea = totals[:conscarea_f] + totals[:conscarea_c] + totals[:conscarea_o]
  popul     = totals[:popul_f]     + totals[:popul_c]     + totals[:popul_o]
  pavearea  = totals[:pavearea_f]  + totals[:pavearea_c]  + totals[:pavearea_o]
  roofarea  = totals[:roofarea_f]  + totals[:roofarea_c]  + totals[:roofarea_o]
  permarea  = totals[:permarea_f]  + totals[:permarea_c]  + totals[:permarea_o]
  tradeflow = totals[:tradeflow] * 1000.0
  baseflow  = totals[:baseflow]  * 1000.0

  File.open(csv_save_loc, 'w') do |f|
    f.puts header.to_csv
    arr = ['Total']
    arr << format('%.2f', totscarea)
    arr << format('%.2f', conscarea)
    arr << format('%.2f', pavearea)
    arr << format('%.2f', roofarea)
    arr << format('%.2f', permarea)
    arr << format('%.1f', popul)
    arr << format('%.2f', tradeflow)
    arr << format('%.2f', baseflow)
    f.puts arr.to_csv
  end

  log "Wrote summary CSV with #{sccount} selected subcatchments to #{csv_save_loc}"
  WSApplication.message_box('Routine completed successfully.', 'OK', 'Information', nil)
rescue StandardError => e
  log "Aborted: #{e.message}"
  WSApplication.message_box("Error: #{e.message}", 'OK', 'Error', nil) rescue nil
ensure
  log 'fix_UI_script_Output CSV of calcs based on Subcatchment Data.rb finished.'
end
