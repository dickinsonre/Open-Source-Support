# frozen_string_literal: true
# ---------------------------------------------------------------------------
# fix_ICM SWMM All Tables.rb
#
# Purpose : Counts row objects in every known ICM SWMM (sw_*) table in the
#           current network and prints a tabular summary.
# Inputs  : Active ICM SWMM current_network.
# Outputs : Console table.
# Type    : UI script.
# Hardening:
#   * frozen_string_literal pragma
#   * Validates current_network not nil
#   * Per-table rescue so unknown tables do not abort the run
#   * begin/rescue/ensure around main logic
#   * Timestamped logging
# ---------------------------------------------------------------------------

def log(msg)
  puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] #{msg}"
end

begin
  net = WSApplication.current_network
  raise 'Error: current network not found' if net.nil?

  table_names = %w[
    sw_conduit sw_node sw_uh sw_uh_group sw_weir sw_pump sw_orifice sw_outlet
    sw_subcatchment sw_suds_control sw_aquifer sw_snow_pack sw_raingage
    sw_curve_control sw_curve_pump sw_curve_rating sw_curve_shape
    sw_curve_storage sw_curve_tidal sw_curve_weir sw_curve_underdrain
    sw_land_use sw_pollutant sw_polygon sw_General_line
    sw_spatial_rain_source sw_spatial_rain_zone sw_transect sw_tvd_connector
    sw_soil sw_2d_zone sw_mesh_zone sw_porous_polygon sw_porous_wall
    sw_roughness_zone sw_mesh_level_zone sw_roughness_definition
    sw_2d_boundary_line sw_head_unit_discharge
  ]

  log "Counting rows in #{table_names.length} sw_* tables..."
  table_names.each do |table_name|
    begin
      table_rows = net.row_objects(table_name)
      if table_rows.nil?
        printf "%-50s %-s\n", "ICM SWMM Elements #{table_name}", 'N/A (nil)'
        next
      end
      number_of_rows = 0
      table_rows.each { |_| number_of_rows += 1 }
      printf "%-50s %-d\n", "ICM SWMM Elements #{table_name}", number_of_rows
    rescue StandardError => e
      printf "%-50s %-s\n", "ICM SWMM Elements #{table_name}", "ERROR: #{e.message}"
    end
  end
rescue StandardError => e
  log "Aborted: #{e.message}"
ensure
  log 'fix_ICM SWMM All Tables.rb finished.'
end
