# frozen_string_literal: true
# Link user number statistics (InfoWorks)
begin
  net = WSApplication.current_network
  exit 1 if net.nil?

  net.clear_selection

  database_fields = ['us_invert', 'ds_invert', 'conduit_length', 'conduit_height', 'conduit_width',
                     'number_of_barrels', 'user_number_1', 'user_number_2', 'user_number_3',
                     'user_number_4', 'user_number_5', 'user_number_6', 'user_number_7',
                     'user_number_8', 'user_number_9', 'user_number_10']

  fields_data = {}
  database_fields.each { |field| fields_data[field] = [] }

  row_count = 0

  net.row_objects('hw_conduit')&.each do |ro|
    row_count += 1
    database_fields.each { |field| fields_data[field] << ro[field] if ro[field] }
  end

  database_fields.each do |field|
    data = fields_data[field]
    next if data.empty?

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

rescue => e
  puts "[ERROR] #{e.message}"
  exit 1
ensure
  puts "[#{Time.now}] Script completed"
end
