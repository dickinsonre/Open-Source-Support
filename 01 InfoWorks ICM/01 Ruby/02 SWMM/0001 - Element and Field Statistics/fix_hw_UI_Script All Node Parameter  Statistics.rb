# frozen_string_literal: true
# Calculate node parameter statistics (InfoWorks)
#
# HARDENING APPLIED:
#   - Added frozen_string_literal pragma
#   - Wrapped in begin/rescue/ensure for error handling
#   - Validates network is open and accessible
#   - Nil-safety for all method calls
#   - Validates data before statistics
#   - Handles scenario iterations safely

begin
  puts "[#{Time.now}] Starting node parameter statistics"

  db = WSApplication.current_database
  if db.nil?
    puts "[#{Time.now}] ERROR: No database is open"
    exit 1
  end

  my_network = WSApplication.current_network
  if my_network.nil?
    puts "[#{Time.now}] ERROR: No network is currently open"
    exit 1
  end

  my_object = my_network.model_object
  if my_object.nil?
    puts "[#{Time.now}] ERROR: Could not get model object"
    exit 1
  end

  # Get the parent ID and type of the current object
  p_id = my_object.parent_id
  p_type = my_object.parent_type

  # Retrieve the parent object from the database
  parent_object = db.model_object_from_type_and_id(p_type, p_id)
  unless parent_object
    puts "[#{Time.now}] ERROR: Could not retrieve parent object"
    exit 1
  end

  # Loop through the hierarchy of parent objects
  (0..999).each do
    break if parent_object.nil?
    puts "Parent Object: #{parent_object.name}"

    temp_p_id = parent_object.parent_id
    temp_p_type = parent_object.parent_type

    break if temp_p_id == 0

    parent_object = db.model_object_from_type_and_id(temp_p_type, temp_p_id)
  end

  # Define database fields for an InfoWorks subcatchment
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

  net = WSApplication.current_network
  if net.nil?
    puts "[#{Time.now}] ERROR: Network is not available"
    exit 1
  end

  net.clear_selection

  # Loop through each scenario
  net.scenarios do |s|
    current_scenario = net.current_scenario = s
    puts "[#{Time.now}] Scenario: #{net.current_scenario}"

    # Prepare hash for storing data of each field
    fields_data = {}
    database_fields.each { |field| fields_data[field] = [] }

    # Initialize the count of processed rows
    row_count = 0

    # Collect data for each field
    net.row_objects('hw_subcatchment')&.each do |ro|
      row_count += 1
      database_fields.each do |field|
        value = ro[field] || 0
        fields_data[field] << value
      end
    end

    # Print statistics for each field
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
             field, row_count, min_value, max_value, mean_value, standard_deviation, total_value)
    end
  end

  puts "[#{Time.now}] Analysis complete"

rescue => e
  puts "[#{Time.now}] ERROR: #{e.class} - #{e.message}"
  puts "Backtrace:"
  puts e.backtrace.first(5).join("\n")
  exit 1
ensure
  puts "[#{Time.now}] Script execution completed"
end
