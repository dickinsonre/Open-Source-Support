# frozen_string_literal: true

# =============================================================================
# fix_sw_change All Node, Link  and Subs ID.rb
# -----------------------------------------------------------------------------
# Purpose : Rename every node, link and subcatchment in an ICM SWMM (sw_*)
#           network to sequential IDs (N_n, L_n, S_n).
# Inputs  : Current open sw_* network.
# Outputs : All affected row objects renamed and written.
# UI / EX : UI script (uses current_network and transaction_begin/commit).
# Hardening:
#   - frozen_string_literal
#   - Header block, begin/rescue/ensure
#   - Validates network and required collections not nil/empty
#   - Pre-flight collision detection across the proposed prefix sets
#   - Wraps transaction in rescue with rollback on any error
#   - Timestamped progress logging
#   - Preserves original behaviour
# =============================================================================

require 'set'

def ts
  Time.now.strftime('%Y-%m-%d %H:%M:%S')
end

def detect_collisions(net, table, prefix, count, ids_being_renamed)
  proposed = (1..count).map { |i| "#{prefix}#{i}" }
  conflicts = []
  net.row_objects(table).each do |obj|
    id = obj.id
    next if id.nil?
    next if ids_being_renamed.include?(id)
    conflicts << id if proposed.include?(id)
  end
  conflicts
end

def update_ids(rows, prefix)
  number = 1
  rows.each do |obj|
    obj.id = "#{prefix}#{number}"
    number += 1
    obj.write
  end
  number - 1
end

begin
  puts "[#{ts}] Starting sw_ Change All Node, Link and Sub IDs."

  net = WSApplication.current_network
  raise 'Current network not found.' if net.nil?

  nodes_ro = net.row_objects('_nodes')
  links_ro = net.row_objects('_links')
  subs_ro  = net.row_objects('_subcatchments')
  raise 'Required object collections not found.' if nodes_ro.nil? || links_ro.nil? || subs_ro.nil?

  node_ids_set = Set.new(nodes_ro.map(&:id).compact)
  link_ids_set = Set.new(links_ro.map(&:id).compact)
  sub_ids_set  = Set.new(subs_ro.map(&:id).compact)

  node_conflicts = detect_collisions(net, '_nodes', 'N_', nodes_ro.size, node_ids_set)
  link_conflicts = detect_collisions(net, '_links', 'L_', links_ro.size, link_ids_set)
  sub_conflicts  = detect_collisions(net, '_subcatchments', 'S_', subs_ro.size, sub_ids_set)

  if !node_conflicts.empty? || !link_conflicts.empty? || !sub_conflicts.empty?
    puts "[#{ts}] COLLISIONS DETECTED - aborting before any write:"
    node_conflicts.each { |c| puts "  node id collision: #{c}" }
    link_conflicts.each { |c| puts "  link id collision: #{c}" }
    sub_conflicts.each  { |c| puts "  sub  id collision: #{c}" }
    raise 'ID collisions detected - resolve manually before re-running.'
  end

  net.transaction_begin
  begin
    puts "[#{ts}] Node IDs updated: #{update_ids(nodes_ro, 'N_')}"
    puts "[#{ts}] Link IDs updated: #{update_ids(links_ro, 'L_')}"
    puts "[#{ts}] Sub  IDs updated: #{update_ids(subs_ro, 'S_')}"
    net.transaction_commit
    puts "[#{ts}] Transaction committed."
  rescue StandardError => txn_e
    net.transaction_rollback
    raise txn_e
  end
rescue StandardError => e
  puts "[#{ts}] ERROR: #{e.message}"
  puts e.backtrace&.first(5)&.join("\n")
ensure
  puts "[#{ts}] Script finished."
end
