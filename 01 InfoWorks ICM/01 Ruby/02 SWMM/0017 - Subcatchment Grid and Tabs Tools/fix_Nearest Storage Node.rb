# frozen_string_literal: true
# =============================================================================
# fix_Nearest Storage Node.rb
# =============================================================================
# Purpose:
#   Hardened version of the "Connect each subcatchment with blank node_id to
#   the nearest storage node" helper. Iterates hw_subcatchment rows that have
#   no node_id set, computes Euclidean distance to every hw_node whose
#   node_type is "storage", and writes the nearest node id back.
#
# Inputs:
#   - Current network with hw_subcatchment + hw_node rows
#
# Outputs:
#   - Updates hw_subcatchment.node_id where blank
#   - Console log per match
#
# UI vs Exchange: UI script.
#
# Hardening notes:
#   - frozen_string_literal, timestamped logging
#   - begin/rescue/ensure with transaction rollback on raise
#   - Builds storage-node array once (O(N+M) instead of N*M tables walks)
#   - Per-row rescue; nil-safe x/y
# =============================================================================

def ts_log(msg)
  puts "[#{Time.now.strftime('%H:%M:%S')}] #{msg}"
end

begin
  ts_log "Starting Nearest Storage Node"

  net = WSApplication.current_network
  raise "No current network." if net.nil?

  storage_nodes = []
  net.row_objects('hw_node').each do |n|
    next if n.nil?
    nt = n.node_type rescue nil
    next unless nt && nt.to_s.downcase == "storage"
    next if n.x.nil? || n.y.nil?
    storage_nodes << [n.node_id, n.x.to_f, n.y.to_f]
  end
  ts_log "Storage nodes available: #{storage_nodes.size}"
  if storage_nodes.empty?
    ts_log "No storage nodes - nothing to do."
    return
  end

  net.transaction_begin
  begin
    matched = 0
    net.row_objects('hw_subcatchment').each do |sub|
      next if sub.nil?
      begin
        next unless (sub.node_id.to_s == "" rescue true)
        next if sub.x.nil? || sub.y.nil?
        sx = sub.x.to_f
        sy = sub.y.to_f
        di = Float::INFINITY
        nearest = ''
        storage_nodes.each do |id, x, y|
          tdi = Math.sqrt((sx - x)**2 + (sy - y)**2)
          if tdi < di
            di = tdi
            nearest = id
          end
        end
        next if nearest.to_s.empty?
        ts_log "#{sub['subcatchment_id']} -> #{nearest} (#{'%.3f' % di})"
        sub['node_id'] = nearest
        sub.write
        matched += 1
      rescue => e
        ts_log "Failed for #{sub&.subcatchment_id}: #{e.message}"
      end
    end
    net.transaction_commit
    ts_log "Updated #{matched} subcatchment(s)"
  rescue => e
    net.transaction_cancel rescue nil
    raise
  end

rescue => e
  ts_log "FATAL: #{e.class}: #{e.message}"
  puts e.backtrace.first(5).join("\n") if e.backtrace
ensure
  ts_log "Nearest Storage Node finished"
end
