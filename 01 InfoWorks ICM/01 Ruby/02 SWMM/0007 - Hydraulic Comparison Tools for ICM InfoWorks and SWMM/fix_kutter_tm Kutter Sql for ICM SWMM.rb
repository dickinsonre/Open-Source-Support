# frozen_string_literal: true

# Purpose: Calculate Kutter's formula capacity for all links at various fill levels
# Inputs: Network links (full, 3/4, 1/2 capacity)
# Outputs: Console table with link ID, diameter, slope, Manning's N, capacities
# Type: EX Script (direct link iteration)
# Hardening: nil-safety, zero-guard on division, property validation

begin
  net = WSApplication.current_network
  raise "Network is nil" if net.nil?

  puts "[#{Time.now.strftime('%H:%M:%S')}] Starting Kutter formula capacity calculation"

  link_count = 0
  net.row_objects('_links')&.each do |link|
    begin
      link_count += 1

      conduit_height = link.conduit_height.to_f rescue 0.0
      gradient = link.gradient.to_f rescue 0.0
      roughness_n = link.bottom_roughness_N.to_f rescue 0.013

      raise "Invalid conduit height (#{conduit_height})" if conduit_height <= 0.0
      raise "Invalid gradient (#{gradient})" if gradient < 0.0
      raise "Invalid Manning's N (#{roughness_n})" if roughness_n <= 0.0

      # Full capacity
      full_numerator = 41.65 + (0.00281 / (gradient / 100.0 + 0.0001)) + (1.811 / roughness_n)
      full_denominator = 1.0 + (full_numerator * roughness_n / ((conduit_height / 48.0)**0.5 + 0.0001))
      full_capacity = (((conduit_height / 12.0)**2) * 0.78539) * (full_numerator / full_denominator) * (((conduit_height / 48.0) * gradient / 100.0)**0.5)

      # 3/4 capacity
      theta = 2.0944
      three_q_numerator = 41.65 + (0.00281 / (gradient / 100.0 + 0.0001)) + (1.811 / roughness_n)
      three_q_denominator = 1.0 + (three_q_numerator * roughness_n / ((conduit_height / 39.78)**0.5 + 0.0001))
      three_quarter_capacity = (((conduit_height / 12.0)**2) * 0.78539 - ((conduit_height / 24.0)**2) * ((theta - Math.sin(theta)) / 2.0)) * (three_q_numerator / three_q_denominator) * (((conduit_height / 39.78) * gradient / 100.0)**0.5)

      half_capacity = 0.5 * full_capacity
      pfc = link.Capacity.to_f rescue 0.0

      if link_count == 1
        puts "%-10s %-20s %-15s %-25s %-30s %-25s %-25s %-25s" % ['Link ID', 'Diameter (inches)', 'Slope (ft/ft)', "Manning's N Roughness", 'ICM Calculated Capacity (CFS)', "Kutter's Full Capacity (CFS)", "Kutter's 3/4 Capacity (CFS)", "Kutter's 1/2 Capacity (CFS)"]
      end

      puts "%-10s %-20.4f %-15.4f %-25.4f %-30.4f %-25.4f %-25.4f %-25.4f" % [link.id, conduit_height, gradient / 100.0, roughness_n, pfc, full_capacity, three_quarter_capacity, half_capacity]

    rescue => e
      puts "[#{Time.now.strftime('%H:%M:%S')}] Error processing link #{link.id}: #{e.message}"
    end
  end

  puts "[#{Time.now.strftime('%H:%M:%S')}] Completed: processed #{link_count} links"

rescue => e
  puts "[#{Time.now.strftime('%H:%M:%S')}] Fatal error: #{e.message}"
  puts e.backtrace.first(5)
ensure
  puts "[#{Time.now.strftime('%H:%M:%S')}] Script ended"
end
