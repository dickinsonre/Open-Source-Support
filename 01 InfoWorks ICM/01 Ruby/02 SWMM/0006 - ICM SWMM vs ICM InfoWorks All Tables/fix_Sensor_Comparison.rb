# frozen_string_literal: true
# ---------------------------------------------------------------------------
# fix_Sensor_Comparison.rb
#
# Purpose : Plot ICM model results vs measured sensor data for a fixed set of
#           pipe locations.  Generates one line graph per location plus a
#           combined scatter.
# Inputs  : - Sensor data text files (one per location) in a user-chosen
#             folder via WSApplication.folder_dialog.
#           - Active InfoWorks ICM current_network with results loaded.
# Outputs : Graph windows via WSApplication.graph and console variance.
# Type    : UI script.
# Hardening:
#   * frozen_string_literal pragma
#   * Validates folder dialog not cancelled and folder exists
#   * Validates current_network not nil and timesteps available
#   * Verifies sensor file exists before IO.readlines
#   * Skips unknown pipes via rescue/next
#   * begin/rescue/ensure around main logic
#   * Timestamped logging
# Source  : https://github.com/ngerdts7/ICM_Tools123
# ---------------------------------------------------------------------------

require 'date'

def log(msg)
  puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] #{msg}"
end

begin
  sensor_dir = WSApplication.folder_dialog('Select a folder for sensor data files', true)
  raise 'Folder dialog cancelled.' if sensor_dir.nil? || sensor_dir.to_s.empty?
  raise "Sensor folder does not exist: #{sensor_dir}" unless File.directory?(sensor_dir)

  net = WSApplication.current_network
  raise 'No current network is open.' if net.nil?

  n = net.timestep_count
  raise 'Network has no timesteps loaded (run a simulation first).' if n.nil? || n.zero?

  locations = {}
  locations['50135.1'] = { 'sensor_file' => 'sensor_1.txt', 'output' => 'us_flow', 'symbol' => 'Cross',  'Color' => WSApplication.colour(0, 0, 255) }
  locations['50009.1'] = { 'sensor_file' => 'sensor_2.txt', 'output' => 'us_flow', 'symbol' => 'Circle', 'Color' => WSApplication.colour(0, 255, 0) }
  locations['72332.1'] = { 'sensor_file' => 'sensor_3.txt', 'output' => 'us_flow', 'symbol' => 'Square', 'Color' => WSApplication.colour(255, 0, 0) }
  locations['72346.1'] = { 'sensor_file' => 'sensor_4.txt', 'output' => 'us_flow', 'symbol' => 'Star',   'Color' => WSApplication.colour(0, 0, 0) }

  graph_window = {}
  graph_window['YAxisLabel'] = 'Flow rate (ft3/s)'
  graph_window['IsTime']     = true

  icm_color    = WSApplication.colour(0, 0, 255)
  sensor_color = WSApplication.colour(255, 0, 0)

  scatter_trace = []

  locations.each do |location, options|
    begin
      sensor_path = File.join(sensor_dir, options['sensor_file'])
      unless File.exist?(sensor_path)
        log "Skipping #{location}: sensor file not found at #{sensor_path}"
        next
      end

      sensor_data = File.readlines(sensor_path)
      sensor      = sensor_data.slice(0, n)

      pipe = net.row_object('hw_conduit', location)
      if pipe.nil?
        log "Skipping #{location}: hw_conduit row not found"
        next
      end

      results = pipe.results('us_flow')
      if results.nil? || results.empty?
        log "Skipping #{location}: no us_flow results"
        next
      end

      squared_difference = 0.0
      results.each_index do |t|
        s_val = sensor[t] ? sensor[t].to_f : 0.0
        squared_difference += (results[t] - s_val)**2
      end

      traces = []
      traces << { 'Title' => location,             'TraceColour' => icm_color,    'LineType' => 'Solid', 'Marker' => 'None', 'XArray' => net.list_timesteps, 'YArray' => results }
      traces << { 'Title' => options['sensor_file'],'TraceColour' => sensor_color, 'LineType' => 'Solid', 'Marker' => 'None', 'XArray' => net.list_timesteps, 'YArray' => sensor }
      scatter_trace << { 'Title' => location, 'LineType' => 'None', 'Marker' => options['symbol'], 'SymbolColour' => options['Color'], 'XArray' => sensor, 'YArray' => results }

      graph_window['WindowTitle'] = location
      graph_window['GraphTitle']  = "#{location} Variance = #{(squared_difference / n)}"
      graph_window['Traces']      = traces
      WSApplication.graph(graph_window)
    rescue StandardError => loc_err
      log "Location #{location} failed: #{loc_err.message}"
    end
  end

  unless scatter_trace.empty?
    graph_window['WindowTitle'] = 'Scatter Comparison of all locations'
    graph_window['GraphTitle']  = ''
    graph_window['Traces']      = scatter_trace
    graph_window['IsTime']      = false
    graph_window['YAxisLabel']  = 'Flow rate (ft3/s)'
    graph_window['XAxisLabel']  = 'Flow rate (ft3/s)'
    WSApplication.graph(graph_window)
  end
rescue StandardError => e
  log "Aborted: #{e.message}"
ensure
  log 'fix_Sensor_Comparison.rb finished.'
end
