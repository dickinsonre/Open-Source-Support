# frozen_string_literal: true
# Calculate subcatchment parameter statistics (InfoWorks)
#
# HARDENING APPLIED:
#   - Added frozen_string_literal pragma
#   - Wrapped in begin/rescue/ensure for error handling
#   - Validates network is open before proceeding
#   - Nil-safety for all method calls
#   - Validates data before calculations

begin
  puts "[#{Time.now}] Starting subcatchment parameter statistics"

  net = WSApplication.current_network
  if net.nil?
    puts "[#{Time.now}] ERROR: No network is currently open"
    exit 1
  end

  net.clear_selection

  database_fields = [
    "population",
    "base_flow",
    "trade_flow",
    "additional_foul_flow",
    "user_number_1",
    "user_number_2",
    "user_number_3",
    "user_number_4",
    "user_number_5",
    "user_number_6",
    "user_number_7",
    "user_number_8",
    "user_number_9",
    "user_number_10"
  ]

  fields_data = {}
  database_fields.each { |field| fields_data[field] = [] }

  row_count = 0

  net.row_objects('hw_subcatchment')&.each do |ro|
    row_count += 1
    database_fields.each do |field|
      value = ro[field] || 0
      fields_data[field] << value
    end
  end

  database_fields.each do |field|
    data = fields_data[field]

    if data.empty?
      puts "[#{Time.now}] #{field} has no data!"
      next
    end

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

  puts "[#{Time.now}] Analysis complete"

rescue => e
  puts "[#{Time.now}] ERROR: #{e.class} - #{e.message}"
  puts e.backtrace.first(5).join("\n")
  exit 1
ensure
  puts "[#{Time.now}] Script execution completed"
end
