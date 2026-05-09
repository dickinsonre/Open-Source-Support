# frozen_string_literal: true
# ---------------------------------------------------------------------------
# fix_sw_UI_Script_Calculate statistics for baseline data.rb
#
# Purpose : Walk all sw_node rows, collect their additional_dwf baseline
#           values, and print summary statistics in MGD and GPM.
# Inputs  : Active ICM SWMM current_network.
# Outputs : Console summary lines.
# Type    : UI script (read-only).
# Hardening:
#   * frozen_string_literal pragma
#   * Validates current_network not nil
#   * Nil-safe iteration over additional_dwf
#   * begin/rescue/ensure around main logic
#   * Timestamped logging
# ---------------------------------------------------------------------------

def log(msg)
  puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] #{msg}"
end

begin
  net = WSApplication.current_network
  raise 'No current network is open.' if net.nil?

  row_count = 0
  baseline_data = []

  net.row_objects('sw_node').each do |ro|
    next if ro.nil?
    (ro.additional_dwf || []).each do |adwf|
      next if adwf.nil?
      row_count += 1
      puts "#{ro.id}, #{ro.bf_pattern_1}"
      baseline_data << adwf.baseline.to_f if adwf.baseline
    end
  end

  if baseline_data.empty?
    puts 'baseline has no data!'
  else
    min_value = baseline_data.min
    max_value = baseline_data.max
    sum = baseline_data.inject(0.0) { |a, v| a + v }
    mean_value = sum / baseline_data.size
    variance = baseline_data.inject(0.0) { |a, v| a + (v - mean_value)**2 } / baseline_data.size
    std_dev = Math.sqrt(variance)

    printf("%-30s | Row Count: %-10d | Min: %-10.3f | Max: %-10.3f | Mean: %-10.3f | Std Dev: %-10.2f | Total: %-10.2f\n",
           'baseline, MGD', row_count, min_value, max_value, mean_value, std_dev, sum)
    printf("%-30s | Row Count: %-10d | Min: %-10.3f | Max: %-10.3f | Mean: %-10.3f | Std Dev: %-10.2f | Total: %-10.2f\n",
           'baseline, GPM', row_count,
           min_value * 694.44, max_value * 694.44, mean_value * 694.44, std_dev * 694.44, sum * 694.44)
  end
rescue StandardError => e
  log "Aborted: #{e.message}"
ensure
  log 'fix_sw_UI_Script_Calculate statistics for baseline data.rb finished.'
end
