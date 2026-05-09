# frozen_string_literal: true
# =============================================================================
# fix_sw_UI_Script_ Make_Subcatchments_From_Imported_InfoSewer_Manholes.rb
# =============================================================================
# Purpose:
#   Hardened version of the SWMM-side script that creates one sw_subcatchment
#   per unique (x, y) coordinate of imported nodes (typically after importing
#   InfoSewer manholes into ICM SWMM).
#
# Inputs:
#   - Current network with imported sw_node objects
#
# Outputs:
#   - One new sw_subcatchment per unique node coordinate, default area 0.10
#
# UI vs Exchange:
#   UI script - uses WSApplication.current_network and transactions.
#
# Hardening notes:
#   - Validates network and collections, skips nil/no-coord nodes
#   - Per-row rescue so a single failure doesn't kill the batch
#   - Transaction committed only on success, cancelled on raise
#   - Timestamped progress logging
# =============================================================================

def ts_log(msg)
  puts "[#{Time.now.strftime('%H:%M:%S')}] #{msg}"
end

begin
  ts_log "Starting Make Subcatchments From Imported InfoSewer Manholes (sw_)"

  net = WSApplication.current_network
  raise "Error: current network not found" if net.nil?

  nodes_roc = net.row_object_collection('sw_node')
  raise "Error: nodes collection not found" if nodes_roc.nil?

  nodes_ro = net.row_objects('sw_node')
  subcatchments_ro = net.row_objects('sw_subcatchment')
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
    nodes_hash_map.each do |_coords, nodes|
      begin
        n = nodes.first
        next if n.nil?
        sub = net.new_row_object('sw_subcatchment')
        sub.subcatchment_id = n.id
        sub.x = n.x
        sub.y = n.y
        sub.area = 0.10
        sub.write
        created += 1
      rescue => e
        failed += 1
        ts_log "Failed creating subcatchment for #{n&.id}: #{e.message}"
      end
    end
    net.transaction_commit
  rescue => e
    net.transaction_cancel rescue nil
    raise
  end

  printf "%-30s %-d\n", "Number of SW Nodes...", nodes_ro.count
  printf "%-30s %-d\n", "Number of SW Subcatchments...", subcatchments_ro.count
  printf "%-30s %-d\n", "Number of New Subcatchments...", created

rescue => e
  ts_log "FATAL: #{e.class}: #{e.message}"
  puts e.backtrace.first(5).join("\n") if e.backtrace
ensure
  ts_log "Make-Subcatchments (sw) finished"
end
