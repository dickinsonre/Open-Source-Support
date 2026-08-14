# frozen_string_literal: true

# =============================================================================
# fix_2_split_links_around_node.rb
# -----------------------------------------------------------------------------
# Purpose : For every selected node, split each upstream and downstream link
#           a configurable distance away from the node.
# Inputs  : Current network with at least one selected node. User-supplied
#           distance via input_box (default 1.5).
# Outputs : New nodes / split links along the connections.
# UI / EX : UI script (uses current_network and transaction_begin/commit).
# Hardening:
#   - frozen_string_literal
#   - Header block, begin/rescue/ensure
#   - Validates network not nil and selection non-empty
#   - Validates user-entered distance: not nil/empty and > 0
#   - Wraps transaction in rescue with rollback on error
#   - Per-node rescue so a single failure does not abort the run
#   - Timestamped progress logging
#   - Preserves original behaviour
# =============================================================================

require_relative 'spatial'

def ts
  Time.now.strftime('%Y-%m-%d %H:%M:%S')
end

DEFAULT_DISTANCE = 1.5

begin
  puts "[#{ts}] Starting Split Links Around Nodes."

  raw = WSApplication.input_box('Specify a distance', 'Split Links Around Nodes', DEFAULT_DISTANCE.to_s)
  raise 'Cancelled by user.' if raw.nil?
  raise 'Distance entry was empty.' if raw.to_s.strip.empty?
  distance = raw.to_f
  raise 'Distance must be > 0.' unless distance.positive?
  puts "[#{ts}] Using distance=#{distance}"

  network = WSApplication.current_network
  raise 'No current network is open.' if network.nil?

  selection = network.row_objects_selection('_nodes')
  raise 'No nodes are selected.' if selection.nil? || selection.empty?

  network.transaction_begin
  begin
    processed = 0
    selection.each do |node|
      begin
        InnoSpatial.split_links_around_node(network, node, distance)
        processed += 1
      rescue StandardError => node_e
        puts "[#{ts}] ERROR around node #{node.id}: #{node_e.message}"
      end
    end
    network.transaction_commit
    puts "[#{ts}] Transaction committed. Nodes processed: #{processed}."
  rescue StandardError => txn_e
    network.transaction_rollback
    raise txn_e
  end
rescue StandardError => e
  puts "[#{ts}] FATAL: #{e.message}"
  puts e.backtrace&.first(5)&.join("\n")
ensure
  puts "[#{ts}] Script finished."
end
