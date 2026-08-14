# frozen_string_literal: true

# =============================================================================
# fix_swmm_UI_script_ Change Subcatchment Boundaries.rb
# -----------------------------------------------------------------------------
# Purpose : Prompt the user for network type (SWMM/InfoWorks) and a target
#           number of sides, then reshape every selected subcatchment polygon
#           to a regular N-sided polygon inscribed in its bounding box.
# Inputs  : Current network with selected subcatchments. WSApplication.prompt
#           dialog for network type and shape choice.
# Outputs : Updated boundary geometry on every selected subcatchment.
# UI / EX : UI script (uses current_network, prompt, transaction_begin/commit).
# Hardening:
#   - frozen_string_literal
#   - Header block, begin/rescue/ensure
#   - Validates network not nil
#   - Validates the prompt was not cancelled (parameters not nil/empty)
#   - Validates the chosen number of sides is between 3 and 50
#   - Validates that the resolved subcatchment table exists
#   - Validates polygon has >= 3 vertices before rewriting
#   - Wraps transaction in rescue with rollback on error
#   - Per-polygon rescue
#   - Timestamped progress logging
#   - Preserves original behaviour
# =============================================================================

def ts
  Time.now.strftime('%Y-%m-%d %H:%M:%S')
end

def generate_polygon_boundary(boundary_array, sides)
  sides = 3 if sides < 3
  min_x = boundary_array.each_slice(2).map(&:first).min
  max_x = boundary_array.each_slice(2).map(&:first).max
  min_y = boundary_array.each_slice(2).map(&:last).min
  max_y = boundary_array.each_slice(2).map(&:last).max
  width  = max_x - min_x
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

begin
  puts "[#{ts}] Starting Change Subcatchment Boundaries (prompt-driven)."

  net = WSApplication.current_network
  raise 'No current network is open.' if net.nil?

  parameters = WSApplication.prompt(
    'Select the network type and desired shape for the polygons',
    [
      ['Is this a SWMM network?',  'Boolean', true],
      ['Triangle (3-sided)',       'Boolean', false],
      ['Square (4-sided)',         'Boolean', false],
      ['Pentagon (5-sided)',       'Boolean', false],
      ['Hexagon (6-sided)',        'Boolean', false],
      ['Heptagon (7-sided)',       'Boolean', false],
      ['Octagon (8-sided)',        'Boolean', false],
      ['Nonagon (9-sided)',        'Boolean', false],
      ['Decagon (10-sided)',       'Boolean', false],
      ['Hendecagon (11-sided)',    'Boolean', false],
      ['Dodecagon (12-sided)',     'Boolean', false],
      ['Tridecagon (13-sided)',    'Boolean', false],
      ['Tetradecagon (14-sided)',  'Boolean', false],
      ['Pentadecagon (15-sided)',  'Boolean', true]
    ],
    false
  )

  raise 'Prompt cancelled by user.' if parameters.nil? || parameters.empty?

  is_swmm_network = parameters[0]
  shape_selection = parameters[1..-1]
  prefix = is_swmm_network ? 'sw' : 'hw'

  sides_options = [3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]
  selected_index = shape_selection.find_index { |b| b == true }
  sides = selected_index ? sides_options[selected_index] : 15
  raise "Invalid number of sides (#{sides})." if sides < 3 || sides > 50
  puts "[#{ts}] Network=#{prefix}_subcatchment, sides=#{sides}"

  table_name = "#{prefix}_subcatchment"
  collection = net.row_object_collection(table_name)
  raise "No rows in '#{table_name}'." if collection.nil?

  net.transaction_begin
  begin
    processed = 0
    collection.each do |polygon|
      next unless polygon.selected?

      begin
        boundary_array = polygon.boundary_array
        if boundary_array.nil? || boundary_array.length < 6
          puts "[#{ts}] Skipping #{polygon.id}: < 3 vertices."
          next
        end
        polygon.boundary_array = generate_polygon_boundary(boundary_array, sides)
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
