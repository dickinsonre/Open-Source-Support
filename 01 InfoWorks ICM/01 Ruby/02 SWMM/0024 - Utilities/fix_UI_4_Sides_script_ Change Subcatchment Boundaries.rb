# frozen_string_literal: true

# =============================================================================
# fix_UI_4_Sides_script_ Change Subcatchment Boundaries.rb
# -----------------------------------------------------------------------------
# Purpose : Replace each selected hw_2d_infiltration_zone polygon with a
#           rectangle that matches the polygon's bounding box.
# Inputs  : Current network with selected hw_2d_infiltration_zone rows.
# Outputs : Updated boundary geometry on every selected polygon.
# UI / EX : UI script (uses current_network and transaction_begin/commit).
# Hardening:
#   - frozen_string_literal
#   - Header block, begin/rescue/ensure
#   - Validates network not nil and collection non-empty
#   - Validates polygon has >= 3 points (>= 6 floats) before rewriting
#   - Wraps transaction in rescue with rollback on any error
#   - Per-polygon rescue so one bad polygon does not abort the run
#   - Timestamped progress logging
#   - Preserves original behaviour
# =============================================================================

def ts
  Time.now.strftime('%Y-%m-%d %H:%M:%S')
end

begin
  puts "[#{ts}] Starting hw_2d_infiltration_zone -> rectangle."

  net = WSApplication.current_network
  raise 'No current network is open.' if net.nil?

  collection = net.row_object_collection('hw_2d_infiltration_zone')
  raise 'No hw_2d_infiltration_zone rows found.' if collection.nil?

  net.transaction_begin
  begin
    processed = 0
    collection.each do |polygon|
      next unless polygon.selected?

      begin
        boundary_array = polygon.boundary_array
        if boundary_array.nil? || boundary_array.length < 6
          puts "[#{ts}] Skipping #{polygon.id}: polygon has < 3 vertices."
          next
        end

        min_x = boundary_array.each_slice(2).map(&:first).min
        max_x = boundary_array.each_slice(2).map(&:first).max
        min_y = boundary_array.each_slice(2).map(&:last).min
        max_y = boundary_array.each_slice(2).map(&:last).max
        puts "[#{ts}] #{polygon.id}: x=#{min_x}..#{max_x} y=#{min_y}..#{max_y}"

        rectangle = [min_x, min_y, max_x, min_y, max_x, max_y, min_x, max_y, min_x, min_y]
        polygon.boundary_array = rectangle
        polygon.write
        processed += 1
      rescue StandardError => p_e
        puts "[#{ts}] ERROR on polygon #{polygon.id}: #{p_e.message}"
      end
    end
    net.transaction_commit
    puts "[#{ts}] Committed. Polygons updated: #{processed}."
  rescue StandardError => txn_e
    net.transaction_rollback
    raise txn_e
  end
rescue StandardError => e
  puts "[#{ts}] FATAL: #{e.message}"
  puts e.backtrace&.first(5)&.join("\n")
ensure
  puts "[#{ts}] Script finished."
end
