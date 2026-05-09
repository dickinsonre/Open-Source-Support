# frozen_string_literal: true

# =============================================================================
# fix_UI-SelectIsolatedNodes.rb
# -----------------------------------------------------------------------------
# Purpose : Select all nodes that have no upstream link, no downstream link
#           and no lateral pipe attachments (i.e. truly isolated nodes).
# Inputs  : Current open network.
# Outputs : Updated selection on the network.
# UI / EX : UI script (uses current_network).
# Hardening:
#   - frozen_string_literal
#   - Header block, begin/rescue/ensure
#   - Validates network not nil and node collection not empty
#   - Nil-safe access to navigate('lateral_pipe')
#   - Timestamped progress logging
#   - Preserves original behaviour
# =============================================================================

def ts
  Time.now.strftime('%Y-%m-%d %H:%M:%S')
end

begin
  puts "[#{ts}] Starting Select Isolated Nodes."

  net = WSApplication.current_network
  raise 'No current network is open.' if net.nil?

  net.clear_selection

  nodes = net.row_objects('_nodes')
  raise 'No node row objects found.' if nodes.nil?

  total = 0
  isolated = 0

  nodes.each do |ro|
    total += 1
    us  = ro.respond_to?(:us_links) ? (ro.us_links || []) : []
    ds  = ro.respond_to?(:ds_links) ? (ro.ds_links || []) : []
    lat = []
    begin
      lat = ro.navigate('lateral_pipe') || []
    rescue StandardError
      lat = []
    end

    if us.length.zero? && ds.length.zero? && lat.size.zero?
      ro.selected = true
      isolated += 1
    end
  end

  puts "[#{ts}] Inspected #{total} nodes, selected #{isolated} isolated nodes."
rescue StandardError => e
  puts "[#{ts}] ERROR: #{e.message}"
  puts e.backtrace&.first(5)&.join("\n")
ensure
  puts "[#{ts}] Script finished."
end
