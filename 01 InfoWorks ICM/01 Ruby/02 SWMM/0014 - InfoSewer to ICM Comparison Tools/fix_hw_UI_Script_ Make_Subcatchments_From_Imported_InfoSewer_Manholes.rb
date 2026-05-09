# frozen_string_literal: true
# =============================================================================
# fix_hw_UI_Script_ Make_Subcatchments_From_Imported_InfoSewer_Manholes.rb
# =============================================================================
# Purpose:
#   Hardened version of the script that creates one hw_subcatchment per unique
#   (x, y) coordinate found in the InfoWorks network nodes (typically after
#   importing InfoSewer manholes into ICM InfoWorks).
#
# Inputs:
#   - Current network with imported nodes (hw_node)
#
# Outputs:
#   - One new hw_subcatchment row per unique node coordinate, default area 0.10
#   - Console summary of node/subcatchment counts
#
# UI vs Exchange:
#   UI script - uses WSApplication.current_network and transactions.
#
# Hardening notes:
#   - Validates network and node/subcatchment collections are non-nil
#   - Wraps create logic in a transaction with rollback on error
#   - Per-row rescue so a single failed row doesn't kill the whole batch
#   - Timestamped progress logging
# =============================================================================

def ts_log(msg)
  puts "[#{Time.now.strftime('%H:%M:%S')}] #{msg}"
end

begin
  ts_log "Starting Make Subcatchments From Imported InfoSewer Manholes (hw_)"

  net = WSApplication.current_network
  raise "Error: current network not found" if net.nil?

  nodes_roc = net.row_object_collection('hw_node')
  raise "Error: nodes collection not found" if nodes_roc.nil?

  nodes_ro = net.row_objects('_nodes')
  subcatchments_ro = net.row_objects('hw_subcatchment')
  raise "Error: nodes or subcatchments not found" if nodes_ro.nil? || subcatchments_ro.nil?

  nodes_hash_map = {}
  nodes_ro.each do |node|
    next if node.nil?
    next if node.x.nil? || node.y.nil?
    nodes_hash_map[[node.x, node.y]] ||= []
    nodes_hash_map[[node.x, node.y]] << node
  end
  ts_log "Unique node coordinates: #{nodes_hash_map.size}"

  created = 0
  failed = 0
  net.transaction_begin
  begin
    nodes_hash_map.each do |coordinates, nodes|
      begin
        n = nodes.first
        next if n.nil?
        sub = net.new_row_object('hw_subcatchment')
        sub.subcatchment_id = n.id
        sub.x = n.x
        sub.y = n.y
        sub.total_area = 0.10
        sub.write
        created += 1
      rescue => e
        failed += 1
        ts_log "Failed to create subcatchment for #{coordinates.inspect}: #{e.message}"
      end
    end
    net.transaction_commit
    ts_log "Transaction committed (#{created} created, #{failed} failed)"
  rescue => e
    net.transaction_cancel rescue nil
    raise
  end

  printf "%-30s %-d\n", "Number of HW Nodes...", nodes_ro.count
  printf "%-30s %-d\n", "Number of HW Subcatchments...", subcatchments_ro.count
  printf "%-30s %-d\n", "Number of New Subcatchments...", created

rescue => e
  ts_log "FATAL: #{e.class}: #{e.message}"
  puts e.backtrace.first(5).join("\n") if e.backtrace
ensure
  ts_log "Make-Subcatchments (hw) finished"
end
