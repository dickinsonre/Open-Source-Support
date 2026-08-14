# frozen_string_literal: true

# =============================================================================
# fix_UI_Generic_Sides_ Change Subcatchment Boundaries.rb
# -----------------------------------------------------------------------------
# Purpose : Replace each selected hw_subcatchment polygon with a regular
#           N-sided polygon inscribed in its bounding box (default 19).
# Inputs  : Current network with selected hw_subcatchment rows.
# Outputs : Updated boundary geometry on every selected subcatchment.
# UI / EX : UI script (uses current_network and transaction_begin/commit).
# Hardening:
#   - frozen_string_literal
#   - Header block, begin/rescue/ensure
#   - Validates network not nil and collection non-empty
#   - Validates polygon has >= 3 vertices before rewriting
#   - Wraps transaction in rescue with rollback on any error
#   - Per-polygon rescue
#   - Timestamped progress logging
#   - Preserves original behaviour
# =============================================================================

def ts
  Time.now.strftime('%Y-%m-%d %H:%M:%S')
end

NUMBER_OF_SIDES = 19

def generate_polygon_boundary(boundary_array, sides)
  sides = 3 if sides < 3
  min_x = boundary_array.each_slice(2).map(&:first).min
  max_x = boundary_array.each_slice(2).map(&:first).max
  min_y = boundary_array.each_slice(2).map(&:last).min
  max_y = boundary_array.each_slice(2).map(&:last).max
  width  = max_x - min_x
  height = max_y - min_y

  poly = []
  sides.times do |i|
    angle = 2 * Math::PI / sides * i
    x = min_x + width * 0.5 + width * 0.5 * Math.cos(angle)
    y = min_y + height * 0.5 + height * 0.5 * Math.sin(angle)
    poly << x << y
  end
  poly << poly[0] << poly[1]
  poly
end

begin
  puts "[#{ts}] Starting hw_subcatchment -> #{NUMBER_OF_SIDES}-gon."

  net = WSApplication.current_network
  raise 'No current network is open.' if net.nil?

  collection = net.row_object_collection('hw_subcatchment')
  raise 'No hw_subcatchment rows found.' if collection.nil?

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

        polygon.boundary_array = generate_polygon_boundary(boundary_array, NUMBER_OF_SIDES)
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
