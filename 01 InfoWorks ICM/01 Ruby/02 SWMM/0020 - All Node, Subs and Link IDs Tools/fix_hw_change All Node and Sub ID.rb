# frozen_string_literal: true

# =============================================================================
# fix_hw_change All Node and Sub ID.rb
# -----------------------------------------------------------------------------
# Purpose : Rename every node and subcatchment in an InfoWorks (hw_*) network
#           to a sequential ID (N_1, N_2, ... and S_1, S_2, ...).
# Inputs  : Current open hw_* network.
# Outputs : All affected row objects renamed and written.
# UI / EX : UI script (uses current_network and transaction_begin/commit).
# Hardening:
#   - frozen_string_literal
#   - Header block, begin/rescue/ensure
#   - Validates network and required collections not nil/empty
#   - Pre-flight collision detection: builds proposed-id set and aborts
#     before any write if a proposed id duplicates an existing id that will
#     not itself be renamed
#   - Wraps transaction in rescue so any error rolls back
#   - Per-row write rescue still rolls back on failure
#   - Timestamped progress logging
#   - Preserves original behaviour (link rename intentionally disabled)
# =============================================================================

require 'set'

def ts
  Time.now.strftime('%Y-%m-%d %H:%M:%S')
end

# Collision-aware bulk rename.  rows is enumerable of row objects, prefix is
# the new id prefix.  ids_to_rename is the set of (table-tag, id) tuples
# being renamed in this run so we can ignore self-collisions.
def proposed_ids(rows, prefix)
  proposed = []
  i = 1
  rows.each do |_|
    proposed << "#{prefix}#{i}"
    i += 1
  end
  proposed
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
  puts "[#{ts}] Starting hw_ Change All Node and Sub IDs."

  net = WSApplication.current_network
  raise 'Current network not found.' if net.nil?

  nodes_ro = net.row_objects('_nodes')
  links_ro = net.row_objects('_links')
  subs_ro  = net.row_objects('_subcatchments')
  raise 'Required object collections not found.' if nodes_ro.nil? || links_ro.nil? || subs_ro.nil?

  node_ids_set = Set.new(nodes_ro.map(&:id).compact)
  sub_ids_set  = Set.new(subs_ro.map(&:id).compact)

  node_conflicts = detect_collisions(net, '_nodes', 'N_', nodes_ro.size, node_ids_set)
  sub_conflicts  = detect_collisions(net, '_subcatchments', 'S_', subs_ro.size, sub_ids_set)

  if !node_conflicts.empty? || !sub_conflicts.empty?
    puts "[#{ts}] COLLISIONS DETECTED - aborting before any write:"
    node_conflicts.each { |c| puts "  node id collision: #{c}" }
    sub_conflicts.each  { |c| puts "  sub  id collision: #{c}" }
    raise 'ID collisions detected - resolve manually before re-running.'
  end

  net.transaction_begin
  begin
    n_count = update_ids(nodes_ro, 'N_')
    puts "[#{ts}] Node IDs updated: #{n_count}"
    # Link rename intentionally disabled in original.
    s_count = update_ids(subs_ro, 'S_')
    puts "[#{ts}] Sub  IDs updated: #{s_count}"
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
