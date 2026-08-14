# frozen_string_literal: true

# =============================================================================
# fix_pudgy penguin subs.rb
# -----------------------------------------------------------------------------
# Purpose : Universal Polygon Geometry and ID Changer for selected
#           subcatchments.  Auto-detects hw_/sw_ network, then reshapes each
#           selected subcatchment to a rectangle, regular polygon, or a
#           pre-defined CUSTOM (penguin) shape, and renames it sequentially.
# Inputs  : Current network with selected subcatchments. Constants at the
#           top of the file control SHAPE_TYPE, NUMBER_OF_SIDES,
#           CUSTOM_SHAPE_POINTS etc.
# Outputs : Updated boundary geometry and renamed subcatchments.
# UI / EX : UI script (uses current_network and transaction_begin/commit).
# Hardening:
#   - frozen_string_literal
#   - Header block, begin/rescue/ensure
#   - Validates network not nil and that hw_ or sw_ subcatchment table exists
#   - Validates polygon has >= 3 vertices before reshaping
#   - Wraps the work in transaction_begin/rescue/transaction_rollback
#   - Per-polygon rescue inside the pass so one bad polygon does not abort
#   - Timestamped progress logging
#   - Preserves original behaviour and CUSTOM penguin shape data
# =============================================================================

def ts
  Time.now.strftime('%Y-%m-%d %H:%M:%S')
end

# --- USER CONFIGURATION ---
NEW_BASE_ID    = 'Penguin'
SHAPE_TYPE     = 'CUSTOM' # 'RECTANGLE' | 'POLYGON' | 'CUSTOM'
NUMBER_OF_SIDES = 6
PRESERVE_AREA  = true
SCALE          = 15.0

CUSTOM_SHAPE_POINTS = [
  [0.0, 20.0], [0.5, 19.8], [0.3, 20.3], [0.8, 20.1], [0.6, 20.5],
  [1.2, 20.0], [3.0, 19.5], [4.5, 18.5], [5.5, 17.0], [6.0, 15.0],
  [6.2, 13.0], [7.5, 11.0], [8.0, 8.0],  [7.8, 5.0],  [7.0, 3.0],
  [6.5, 3.5],
  [6.0, 6.0],  [5.8, 3.0],  [5.0, 1.0],
  [5.5, 0.0],  [4.5, -0.5], [3.0, -0.3], [2.0, 0.0],  [0.0, 0.0]
].freeze

# --- helpers ---
def calculate_polygon_area(boundary_array)
  return 0.0 if boundary_array.nil? || boundary_array.length < 6
  n = boundary_array.length / 2
  area = 0.0
  (0...n - 1).each do |i|
    x1 = boundary_array[i * 2]
    y1 = boundary_array[i * 2 + 1]
    x2 = boundary_array[(i + 1) * 2]
    y2 = boundary_array[(i + 1) * 2 + 1]
    area += (x1 * y2 - x2 * y1)
  end
  area.abs / 2.0
end

def calculate_shape_area(shape_points)
  area = 0.0
  n = shape_points.length
  (0...n - 1).each do |i|
    x1, y1 = shape_points[i]
    x2, y2 = shape_points[i + 1]
    area += (x1 * y2 - x2 * y1)
  end
  if shape_points[0] != shape_points[-1]
    x1, y1 = shape_points[-1]
    x2, y2 = shape_points[0]
    area += (x1 * y2 - x2 * y1)
  end
  area.abs / 2.0
end

def generate_custom_shape_boundary(center_x, center_y, scale, shape_points,
                                   original_area = nil, preserve_area = false)
  full = []
  if shape_points.first[0] == 0 && shape_points.last[0] == 0 && shape_points.size > 2
    right = shape_points
    left  = right[1...-1].map { |p| [-p[0], p[1]] }.reverse
    full = right + left
  else
    full = shape_points
  end

  actual_scale = scale
  if preserve_area && original_area && original_area > 0
    template_area = calculate_shape_area(full)
    actual_scale = Math.sqrt(original_area / template_area) if template_area > 0
  end

  out = []
  full.each do |p|
    out << center_x + (p[0] * actual_scale)
    out << center_y + (p[1] * actual_scale)
  end
  if out[0] != out[-2] || out[1] != out[-1]
    out << out[0] << out[1]
  end
  out
end

def generate_regular_polygon_boundary(boundary_array, sides)
  sides = 3 if sides < 3
  min_x, max_x = boundary_array.each_slice(2).map(&:first).minmax
  min_y, max_y = boundary_array.each_slice(2).map(&:last).minmax
  width  = max_x - min_x
  height = max_y - min_y
  cx = min_x + width / 2.0
  cy = min_y + height / 2.0
  rx = width / 2.0
  ry = height / 2.0

  out = []
  sides.times do |i|
    angle = 2 * Math::PI / sides * i - (Math::PI / 2)
    x = cx + rx * Math.cos(angle)
    y = cy + ry * Math.sin(angle)
    out << x << y
  end
  out << out[0] << out[1]
  out
end

def generate_rectangle_boundary(boundary_array)
  min_x, max_x = boundary_array.each_slice(2).map(&:first).minmax
  min_y, max_y = boundary_array.each_slice(2).map(&:last).minmax
  [min_x, min_y, max_x, min_y, max_x, max_y, min_x, max_y, min_x, min_y]
end

# --- main ---
begin
  puts "[#{ts}] Starting universal polygon geometry & ID changer."

  net = WSApplication.current_network
  raise 'No current network is open.' if net.nil?

  table_name = nil
  table_names = []
  begin
    table_names = net.table_names || []
  rescue StandardError => tne
    raise "Could not enumerate table_names: #{tne.message}"
  end

  table_names.each do |name|
    if name.start_with?('hw_')
      table_name = 'hw_subcatchment'
      puts "[#{ts}] InfoWorks (hw_) network detected."
      break
    elsif name.start_with?('sw_')
      table_name = 'sw_subcatchment'
      puts "[#{ts}] SWMM (sw_) network detected."
      break
    end
  end

  raise "No 'hw_subcatchment' or 'sw_subcatchment' table found in network." if table_name.nil?

  net.transaction_begin
  begin
    objects = net.row_object_collection(table_name)
    raise "No rows in #{table_name}." if objects.nil?

    id_counter = 0
    objects.each do |polygon|
      next unless polygon.selected?

      begin
        boundary_array = polygon.boundary_array
        if boundary_array.nil? || boundary_array.length < 6
          puts "[#{ts}] Skipping #{polygon.id}: < 3 vertices."
          next
        end

        id_counter += 1
        old_id = polygon.id
        new_id = "#{NEW_BASE_ID}_#{id_counter}"
        polygon.id = new_id

        new_boundary = nil
        case SHAPE_TYPE.upcase
        when 'RECTANGLE'
          new_boundary = generate_rectangle_boundary(boundary_array)
        when 'POLYGON'
          new_boundary = generate_regular_polygon_boundary(boundary_array, NUMBER_OF_SIDES)
        when 'CUSTOM'
          original_area = PRESERVE_AREA ? calculate_polygon_area(boundary_array) : nil
          new_boundary = generate_custom_shape_boundary(
            polygon.x, polygon.y, SCALE, CUSTOM_SHAPE_POINTS,
            original_area, PRESERVE_AREA
          )
        else
          puts "[#{ts}] WARNING: invalid SHAPE_TYPE '#{SHAPE_TYPE}' for '#{old_id}'."
        end

        polygon.boundary_array = new_boundary if new_boundary
        polygon.write
        puts "[#{ts}] '#{old_id}' -> '#{new_id}' shape updated."
      rescue StandardError => p_e
        puts "[#{ts}] ERROR on polygon #{polygon.id}: #{p_e.message}"
      end
    end

    if id_counter.zero?
      puts "[#{ts}] No subcatchments selected. Rolling back."
      net.transaction_rollback
    else
      net.transaction_commit
      puts "[#{ts}] Committed. Subcatchments updated: #{id_counter}."
    end
  rescue StandardError => txn_e
    begin
      net.transaction_rollback
    rescue StandardError
      # already rolled back / commit failed at boundary
    end
    raise txn_e
  end
rescue StandardError => e
  puts "[#{ts}] FATAL: #{e.message}"
  puts e.backtrace&.first(5)&.join("\n")
ensure
  puts "[#{ts}] Script finished."
end
