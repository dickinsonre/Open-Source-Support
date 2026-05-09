# frozen_string_literal: true

# =============================================================================
# fix_hw_sw_Header Nodes.rb
# -----------------------------------------------------------------------------
# Purpose : Select header (most-upstream) nodes: nodes that never appear as
#           the downstream node of any link.
# Inputs  : Current open network (hw_* or sw_*).
# Outputs : Updated selection containing every header node.
# UI / EX : UI script (uses current_network).
# Hardening:
#   - frozen_string_literal
#   - Header block, begin/rescue/ensure
#   - Validates network, _nodes and _links collections (not nil / not empty)
#   - Builds a Set of downstream node-ids for O(1) lookup
#   - Skips records with nil ids; per-node rescue
#   - Timestamped progress logging and final count
# =============================================================================

require 'set'

def ts
  Time.now.strftime('%Y-%m-%d %H:%M:%S')
end

begin
  puts "[#{ts}] Starting Header Node detection."

  net = WSApplication.current_network
  raise 'No current network is open.' if net.nil?

  net.clear_selection

  nodes = net.row_objects('_nodes')
  raise '_nodes object collection is empty or unavailable.' if nodes.nil? || nodes.empty?

  links = net.row_objects('_links')
  raise '_links object collection is empty or unavailable.' if links.nil? || links.empty?

  ds_set = Set.new
  links.each do |l|
    nid = l.ds_node_id
    ds_set << nid unless nid.nil?
  end

  selected = 0
  nodes.each do |node|
    nid = node.node_id
    next if nid.nil?
    next if ds_set.include?(nid)
    begin
      node.selected = true
      selected += 1
      puts "[#{ts}] Header node selected: #{nid}"
    rescue StandardError => se
      puts "[#{ts}] WARNING: could not select node '#{nid}': #{se.message}"
    end
  end

  puts "[#{ts}] Total header nodes selected: #{selected}"
rescue StandardError => e
  puts "[#{ts}] ERROR: #{e.message}"
  puts e.backtrace&.first(5)&.join("\n")
ensure
  puts "[#{ts}] Script finished."
end
