# frozen_string_literal: true

# =============================================================================
# fix_UI_script_ Change Subcatchment Boundaries.rb
# -----------------------------------------------------------------------------
# Purpose : Sequentially reshape every selected hw_subcatchment polygon
#           through five geometries: rectangle -> hexagon -> pentagon ->
#           nonagon -> regular 7-gon.
# Inputs  : Current network with selected hw_subcatchment rows.
# Outputs : Updated boundary geometry on every selected polygon (multiple
#           sequential transactions).
# UI / EX : UI script (uses current_network and transaction_begin/commit).
# Hardening:
#   - frozen_string_literal
#   - Header block, begin/rescue/ensure
#   - Validates network not nil and collection non-empty
#   - Validates polygon has >= 3 vertices before each pass
#   - Each pass wrapped in transaction_begin/rescue/transaction_rollback
#   - Per-polygon rescue
#   - Timestamped per-pass progress logging
#   - Preserves original behaviour
# =============================================================================

def ts
  Time.now.strftime('%Y-%m-%d %H:%M:%S')
end

# Helper: extract bounding-box for a flat boundary array (or nil if invalid)
def bbox(boundary_array)
  return nil if boundary_array.nil? || boundary_array.length < 6
  min_x = boundary_array.each_slice(2).map(&:first).min
  max_x = boundary_array.each_slice(2).map(&:first).max
  min_y = boundary_array.each_slice(2).map(&:last).min
  max_y = boundary_array.each_slice(2).map(&:last).max
  [min_x, max_x, min_y, max_y]
end

def square_boundary(min_x, max_x, min_y, max_y)
  [min_x, min_y, max_x, min_y, max_x, max_y, min_x, max_y, min_x, min_y]
end

def hexagon_boundary(min_x, max_x, min_y, max_y)
  width = max_x - min_x
  height = max_y - min_y
  [
    min_x + width * 0.25, min_y,
    min_x + width * 0.75, min_y,
    max_x,                min_y + height * 0.5,
    min_x + width * 0.75, max_y,
    min_x + width * 0.25, max_y,
    min_x,                min_y + height * 0.5,
    min_x + width * 0.25, min_y
  ]
end

def pentagon_boundary(min_x, max_x, min_y, max_y)
  width = max_x - min_x
  height = max_y - min_y
  [
    min_x + width * 0.5, min_y,
    max_x,               min_y + height * 0.4,
    min_x + width * 0.8, max_y,
    min_x + width * 0.2, max_y,
    min_x,               min_y + height * 0.4,
    min_x + width * 0.5, min_y
  ]
end

def nonagon_boundary(min_x, max_x, min_y, max_y)
  width = max_x - min_x
  height = max_y - min_y
  out = []
  9.times do |i|
    angle = 2 * Math::PI / 9 * i
    x = min_x + width * 0.5 + width * 0.5 * Math.cos(angle)
    y = min_y + height * 0.5 + height * 0.5 * Math.sin(angle)
    out << x << y
  end
  out << out[0] << out[1]
  out
end

def n_gon_boundary(min_x, max_x, min_y, max_y, sides)
  sides = 3 if sides < 3
  width = max_x - min_x
  height = max_y - min_y
  out = []
  sides.times do |i|
    angle = 2 * Math::PI / sides * i
    x = min_x + width * 0.5 + width * 0.5 * Math.cos(angle)
    y = min_y + height * 0.5 + height * 0.5 * Math.sin(angle)
    out << x << y
  end
  out << out[0] << out[1]
  out
end

def run_pass(net, label)
  net.transaction_begin
  begin
    processed = 0
    net.row_object_collection('hw_subcatchment').each do |polygon|
      next unless polygon.selected?
      begin
        bb = bbox(polygon.boundary_array)
        if bb.nil?
          puts "[#{ts}] [#{label}] Skipping #{polygon.id}: < 3 vertices."
          next
        end
        new_bnd = yield(bb)
        polygon.boundary_array = new_bnd if new_bnd
        polygon.write
        processed += 1
      rescue StandardError => p_e
        puts "[#{ts}] [#{label}] ERROR on polygon #{polygon.id}: #{p_e.message}"
      end
    end
    net.transaction_commit
    puts "[#{ts}] [#{label}] Committed. Polygons updated: #{processed}."
  rescue StandardError => txn_e
    net.transaction_rollback
    raise txn_e
  end
end

begin
  puts "[#{ts}] Starting hw_subcatchment multi-pass shape sequence."

  net = WSApplication.current_network
  raise 'No current network is open.' if net.nil?

  collection = net.row_object_collection('hw_subcatchment')
  raise 'No hw_subcatchment rows found.' if collection.nil?

  run_pass(net, 'Rectangle')  { |min_x, max_x, min_y, max_y| square_boundary(min_x, max_x, min_y, max_y) }
  run_pass(net, 'Hexagon')    { |min_x, max_x, min_y, max_y| hexagon_boundary(min_x, max_x, min_y, max_y) }
  run_pass(net, 'Pentagon')   { |min_x, max_x, min_y, max_y| pentagon_boundary(min_x, max_x, min_y, max_y) }
  run_pass(net, 'Nonagon')    { |min_x, max_x, min_y, max_y| nonagon_boundary(min_x, max_x, min_y, max_y) }
  run_pass(net, '7-gon')      { |min_x, max_x, min_y, max_y| n_gon_boundary(min_x, max_x, min_y, max_y, 7) }
rescue StandardError => e
  puts "[#{ts}] FATAL: #{e.message}"
  puts e.backtrace&.first(5)&.join("\n")
ensure
  puts "[#{ts}] Script finished."
end
