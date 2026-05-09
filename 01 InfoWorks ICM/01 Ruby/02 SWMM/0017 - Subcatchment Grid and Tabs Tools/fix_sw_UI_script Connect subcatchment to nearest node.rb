# frozen_string_literal: true
# =============================================================================
# fix_sw_UI_script Connect subcatchment to nearest node.rb
# =============================================================================
# Purpose:
#   Hardened helper that, for every selected sw_subcatchment, finds the
#   nearest selected sw_node by Euclidean distance and writes its node id
#   to the subcatchment.outlet_id.
#
# Inputs:  Current network in EDIT mode with selected nodes & subcatchments.
# Outputs: Subcatchment.outlet_id updates.
# UI vs Exchange: UI script.
#
# Hardening notes:
#   - frozen_string_literal, timestamped logging
#   - begin/rescue/ensure with transaction rollback on raise
#   - Per-row rescue; nil-safe x/y
# =============================================================================

def ts_log(msg)
  puts "[#{Time.now.strftime('%H:%M:%S')}] #{msg}"
end

begin
  ts_log "Starting Connect subcatchment to nearest node (sw_)"
  net = WSApplication.current_network
  raise "No current network." if net.nil?

  nodes = []
  net.row_object_collection('sw_node').each do |n|
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
    net.row_object_collection('sw_subcatchment').each do |s|
      next if s.nil?
      next unless (s.selected? rescue false)
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
          s.outlet_id = nearest_id
          s.write
          matched += 1
        end
      rescue => e
        ts_log "Skip #{s&.id}: #{e.message}"
      end
    end
    net.transaction_commit
    ts_log "Matched #{matched}"
  rescue => e
    net.transaction_cancel rescue nil
    raise
  end

rescue => e
  ts_log "FATAL: #{e.class}: #{e.message}"
  puts e.backtrace.first(5).join("\n") if e.backtrace
ensure
  ts_log "Connect-to-nearest-node (sw) finished"
end
