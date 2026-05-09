# frozen_string_literal: true
# ---------------------------------------------------------------------------
# fix_sw_UI_Script_additional_dwf_nodes_icm_swmm.rb
#
# Purpose : Walk all sw_node rows, collect base_flow values and additional_dwf
#           baseline values, and print min/max/mean/std-dev/total stats for
#           each plus the combined set.
# Inputs  : Active ICM SWMM current_network.
# Outputs : Console statistics tables.
# Type    : UI script (read-only).
# Hardening:
#   * frozen_string_literal pragma
#   * Validates current_network not nil
#   * Nil-safe access to additional_dwf and base_flow
#   * begin/rescue/ensure around main logic
#   * Timestamped logging
# ---------------------------------------------------------------------------

def log(msg)
  puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] #{msg}"
end

def print_stats(name, data, row_count)
  if data.nil? || data.empty?
    puts "#{name} has no data!"
    return
  end
  min_value = data.min
  max_value = data.max
  sum = data.inject(0.0) { |a, v| a + v }
  mean_value = sum / data.size
  variance = data.inject(0.0) { |a, v| a + (v - mean_value)**2 } / data.size
  std_dev = Math.sqrt(variance)
  printf("%-30s | Row Count: %-10d | Min: %-10.3f | Max: %-10.3f | Mean: %-10.3f | Std Dev: %-10.2f | Total: %-10.2f\n",
         "#{name}, MGD", row_count, min_value, max_value, mean_value, std_dev, sum)
end

begin
  cn = WSApplication.current_network
  raise 'No current network is open.' if cn.nil?

  row_count = 0
  baseline_data = []
  base_flow_data = []

  cn.row_objects('sw_node').each do |ro|
    next if ro.nil?
    base_flow_data << ro.base_flow.to_f if ro.base_flow
    row_count += 1
    (ro.additional_dwf || []).each do |adwf|
      baseline_data << adwf.baseline.to_f if adwf&.baseline
    end
  end

  print_stats('base_flow',           base_flow_data, row_count)
  print_stats('additional_baseline', baseline_data,  row_count)
  print_stats('Combined',            base_flow_data + baseline_data, row_count)
rescue StandardError => e
  log "Aborted: #{e.message}"
ensure
  log 'fix_sw_UI_Script_additional_dwf_nodes_icm_swmm.rb finished.'
end
