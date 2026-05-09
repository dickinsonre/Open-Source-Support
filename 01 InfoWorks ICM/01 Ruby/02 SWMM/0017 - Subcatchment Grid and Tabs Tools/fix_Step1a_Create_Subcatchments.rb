# frozen_string_literal: true
# =============================================================================
# fix_Step1a_Create_Subcatchments.rb
# =============================================================================
# Purpose:
#   Hardened "Create one hw_subcatchment per unique node coordinate" helper
#   for InfoWorks networks (mirrors fix_hw_UI_Script_ Make_Subcatchments_*).
#
# Inputs:
#   - Current network with hw_node rows
#
# Outputs:
#   - One hw_subcatchment per unique (x, y) with default total_area = 0.10
#
# UI vs Exchange: UI script.
#
# Hardening notes:
#   - frozen_string_literal, timestamped logging
#   - begin/rescue/ensure with transaction rollback on raise
#   - per-row rescue; nil-safe x/y
# =============================================================================

def ts_log(msg)
  puts "[#{Time.now.strftime('%H:%M:%S')}] #{msg}"
end

begin
  ts_log "Starting Step 1a - Create Subcatchments"

  net = WSApplication.current_network
  raise "No current network." if net.nil?

  nodes_roc = net.row_object_collection('hw_node')
  raise "Error: nodes not found" if nodes_roc.nil?

  nodes_ro = net.row_objects('_nodes')
  subcatchments_ro = net.row_objects('hw_subcatchment')
  raise "Error: nodes or subcatchments not found" if nodes_ro.nil? || subcatchments_ro.nil?

  nodes_hash_map = {}
  nodes_ro.each do |node|
    next if node.nil? || node.x.nil? || node.y.nil?
    nodes_hash_map[[node.x, node.y]] ||= []
    nodes_hash_map[[node.x, node.y]] << node
  end

  net.transaction_begin
  begin
    created = 0
    nodes_hash_map.each do |_coords, nodes|
      n = nodes.first
      next if n.nil?
      begin
        sub = net.new_row_object('hw_subcatchment')
        sub.subcatchment_id = n.id
        sub.x = n.x
        sub.y = n.y
        sub.total_area = 0.10
        sub.write
        created += 1
      rescue => e
        ts_log "Skip #{n&.id}: #{e.message}"
      end
    end
    net.transaction_commit
    printf "%-30s %-d\n", "Number of HW Nodes...", nodes_ro.count
    printf "%-30s %-d\n", "Number of HW Subcatchments...", subcatchments_ro.count
    printf "%-30s %-d\n", "Number of New Subcatchments...", created
  rescue => e
    net.transaction_cancel rescue nil
    raise
  end

rescue => e
  ts_log "FATAL: #{e.class}: #{e.message}"
  puts e.backtrace.first(5).join("\n") if e.backtrace
ensure
  ts_log "Step 1a finished"
end
