# frozen_string_literal: true
# =============================================================================
# Hardened: SWMM Conduit (Link) Parameter & User-Number Statistics
# =============================================================================
# Purpose : Calculate min/max/mean/std-dev/total for sw_conduit fields including
#           geometry (us_invert, ds_invert, length, height, width, barrels)
#           and user_number_1 .. user_number_10.
# Inputs  : Currently open SWMM network in InfoWorks ICM.
# Outputs : Tabular printf summary written to the Ruby output console.
# UI/EX   : UI script (run inside ICM via Network -> Run Ruby Script).
# Hardening notes:
#   * frozen_string_literal pragma
#   * begin / rescue / ensure around main logic with timestamped logging
#   * Validates WSApplication.current_network is not nil
#   * Nil-safety with &. on row_objects iteration
#   * Preserves original behavior of print_csv_inflows_file()
# =============================================================================

def print_csv_inflows_file(net)
  # Define database fields for SWMM network conduits (links)
  database_fields = [
    'us_invert',
    'ds_invert',
    'length',
    'conduit_height',
    'conduit_width',
    'number_of_barrels',
    'user_number_1',
    'user_number_2',
    'user_number_3',
    'user_number_4',
    'user_number_5',
    'user_number_6',
    'user_number_7',
    'user_number_8',
    'user_number_9',
    'user_number_10'
  ]

  net.clear_selection
  puts "Scenario     : #{net.current_scenario}"

  # Prepare hash for storing data of each field for database_fields
  fields_data = {}
  database_fields.each { |field| fields_data[field] = [] }

  # Initialize the count of processed rows
  row_count = 0

  # Collect data for each field from sw_conduit
  net.row_objects('sw_conduit')&.each do |ro|
    row_count += 1
    database_fields.each do |field|
      fields_data[field] << ro[field] if ro[field]
    end
  end

  # Print min, max, mean, standard deviation, total, and row count for each field
  database_fields.each do |field|
    data = fields_data[field]
    next if data.nil? || data.empty?

    min_value = data.min
    max_value = data.max
    sum = data.inject(0.0) { |s, val| s + val }
    mean_value = sum / data.size
    sum_of_squares = data.inject(0.0) { |accum, i| accum + (i - mean_value) ** 2 }
    standard_deviation = Math.sqrt(sum_of_squares / data.size)
    total_value = sum

    printf("%-30s | Row Count: %-10d | Min: %-10.3f | Max: %-10.3f | Mean: %-10.3f | Std Dev: %-10.2f | Total: %-10.2f\n",
           field, data.size, min_value, max_value, mean_value, standard_deviation, total_value)
  end
end

begin
  puts "[#{Time.now}] Starting SWMM link user-number statistics"

  net = WSApplication.current_network
  if net.nil?
    puts "[ERROR] No current network. Open a SWMM network and try again."
    exit 1
  end

  print_csv_inflows_file(net)

  puts "[#{Time.now}] Statistics complete"
rescue => e
  puts "[ERROR] #{e.class}: #{e.message}"
  puts e.backtrace.first(5).join("\n") if e.backtrace
  exit 1
ensure
  puts "[#{Time.now}] Script completed"
end
