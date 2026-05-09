# frozen_string_literal: true

# =============================================================================
# fix_hw_sw_Bifurcation Nodes.rb
# -----------------------------------------------------------------------------
# Purpose : Select all bifurcation nodes - nodes that appear as the upstream
#           node of two or more links.
# Inputs  : Current open network (hw_* or sw_*).
# Outputs : Updated selection containing every bifurcation node.
# UI / EX : UI script (uses current_network).
# Hardening:
#   - frozen_string_literal
#   - Header block, begin/rescue/ensure
#   - Validates network not nil
#   - Validates link collection not nil/empty
#   - Skips links with nil us_node_id
#   - Per-node lookup wrapped in rescue (a missing node id will not abort)
#   - Timestamped progress logging and final count
# =============================================================================

def ts
  Time.now.strftime('%Y-%m-%d %H:%M:%S')
end

begin
  puts "[#{ts}] Starting Bifurcation Nodes detection."

  net = WSApplication.current_network
  raise 'No current network is open.' if net.nil?

  net.clear_selection

  links = net.row_objects('_links')
  raise 'No links found in current network.' if links.nil?

  us_node_count = Hash.new(0)
  links.each do |link|
    nid = link.us_node_id
    next if nid.nil?
    us_node_count[nid] += 1
  end

  selected = 0
  us_node_count.each do |node_id, count|
    next unless count > 1
    begin
      n = net.row_object('_nodes', node_id)
      next if n.nil?
      n.selected = true
      selected += 1
      puts "[#{ts}] Bifurcation node: #{node_id} (#{count} outgoing links)."
    rescue StandardError => ne
      puts "[#{ts}] WARNING: cannot select node '#{node_id}': #{ne.message}"
    end
  end

  puts "[#{ts}] Total bifurcation nodes selected: #{selected}"
rescue StandardError => e
  puts "[#{ts}] ERROR: #{e.message}"
  puts e.backtrace&.first(5)&.join("\n")
ensure
  puts "[#{ts}] Script finished."
end
