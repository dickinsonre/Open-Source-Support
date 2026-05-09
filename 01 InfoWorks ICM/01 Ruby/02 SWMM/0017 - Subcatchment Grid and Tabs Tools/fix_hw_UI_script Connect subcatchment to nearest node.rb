# frozen_string_literal: true
# =============================================================================
# fix_hw_UI_script Connect subcatchment to nearest node.rb
# =============================================================================
# Purpose:
#   Hardened helper that, for every selected hw_subcatchment, finds the
#   nearest selected hw_node by Euclidean distance and writes its node_id
#   back to the subcatchment.
#
# Inputs:
#   - Current network in EDIT mode
#   - User selection: at least one hw_node and one hw_subcatchment
#
# Outputs:
#   - Subcatchment.node_id updates
#
# UI vs Exchange: UI script.
#
# Hardening notes:
#   - frozen_string_literal, timestamped logging
#   - begin/rescue/ensure with transaction rollback on raise
#   - per-row rescue; nil-safe x/y; no early-exit unless selection exists
# =============================================================================

def ts_log(msg)
  puts "[#{Time.now.strftime('%H:%M:%S')}] #{msg}"
end

begin
  ts_log "Starting Connect subcatchment to nearest node (hw)"

  net = WSApplication.current_network
  raise "No current network." if net.nil?

  nodes = []
  net.row_object_collection('hw_node').each do |n|
    next if n.nil?
    next unless (n.selected? rescue false)
    next if n.x.nil? || n.y.nil?
    nodes << [n.id, n.x.to_f, n.y.to_f]
  end
  ts_log "Selected nodes: #{nodes.size}"
  if nodes.empty?
    ts_log "No selected nodes - aborting."
    return
  end

  net.transaction_begin
  begin
    matched = 0
    skipped = 0
    net.row_object_collection('hw_subcatchment').each do |s|
      next if s.nil?
      unless (s.selected? rescue false)
        next
      end
      begin
        next if s.x.nil? || s.y.nil?
        sx = s.x.to_f
        sy = s.y.to_f
        nearest_distance = Float::INFINITY
        nearest_id = nil
        nodes.each do |nid, nx, ny|
          d = (sx - nx)**2 + (sy - ny)**2
          if d < nearest_distance
            nearest_distance = d
            nearest_id = nid
          end
        end
        if nearest_id
          s.node_id = nearest_id
          s.write
          matched += 1
        else
          skipped += 1
        end
      rescue => e
        ts_log "Skip #{s&.subcatchment_id}: #{e.message}"
      end
    end
    net.transaction_commit
    ts_log "Matched #{matched}, skipped #{skipped}"
  rescue => e
    net.transaction_cancel rescue nil
    raise
  end

rescue => e
  ts_log "FATAL: #{e.class}: #{e.message}"
  puts e.backtrace.first(5).join("\n") if e.backtrace
ensure
  ts_log "Connect-to-nearest-node (hw) finished"
end
