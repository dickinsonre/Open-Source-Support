# frozen_string_literal: true

# =============================================================================
# fix_Get Minimum X,Y for All Nodes.rb
# -----------------------------------------------------------------------------
# Purpose : Compute and print the min/max X and Y over every node in the
#           current network.
# Inputs  : Current open network.
# Outputs : Console summary with three-decimal min/max coordinates and the
#           current ICM application version.
# UI / EX : UI script (uses current_network).
# Hardening:
#   - frozen_string_literal
#   - Header block, begin/rescue/ensure
#   - Validates network not nil and node collection not empty
#   - Skips nodes whose x or y is nil
#   - Counts considered vs skipped nodes
#   - Timestamped progress logging
#   - Preserves original behaviour
# =============================================================================

def ts
  Time.now.strftime('%Y-%m-%d %H:%M:%S')
end

begin
  puts "[#{ts}] Starting Get Minimum X,Y for All Nodes."

  net = WSApplication.current_network
  raise 'No current network is open.' if net.nil?

  nodes = net.row_objects('_nodes')
  raise 'No nodes found.' if nodes.nil? || nodes.empty?

  min_x = nil
  min_y = nil
  max_x = nil
  max_y = nil
  considered = 0
  skipped = 0

  nodes.each do |node|
    x = node.x
    y = node.y
    if x.nil? || y.nil?
      skipped += 1
      next
    end
    considered += 1

    min_x = x if min_x.nil? || x < min_x
    max_x = x if max_x.nil? || x > max_x
    min_y = y if min_y.nil? || y < min_y
    max_y = y if max_y.nil? || y > max_y
  end

  if considered.zero?
    puts "[#{ts}] No usable node coordinates found (all #{skipped} skipped)."
  else
    puts "[#{ts}] Minimum x, y: #{format('%.3f', min_x)}, #{format('%.3f', min_y)}"
    puts "[#{ts}] Maximum x, y: #{format('%.3f', max_x)}, #{format('%.3f', max_y)}"
    puts "[#{ts}] Considered #{considered} node(s), skipped #{skipped}."
  end

  begin
    puts "Welcome to InfoWorks ICM Version #{WSApplication.version}"
  rescue StandardError
    # version may not be available in some hosts; ignore.
  end
rescue StandardError => e
  puts "[#{ts}] ERROR: #{e.message}"
  puts e.backtrace&.first(5)&.join("\n")
ensure
  puts "[#{ts}] Script finished."
end
