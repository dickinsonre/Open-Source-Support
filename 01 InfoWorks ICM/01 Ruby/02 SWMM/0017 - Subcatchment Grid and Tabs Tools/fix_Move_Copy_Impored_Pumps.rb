# frozen_string_literal: true
# =============================================================================
# fix_Move_Copy_Impored_Pumps.rb (original misspelling of "Imported" preserved)
# =============================================================================
# Purpose:
#   Hardened helper that lists nodes/links/subcatchments/pumps and finds links
#   tagged with user_text_10 == 'Pump'. For each it creates a new hw_pump row
#   bound to the same upstream/downstream node IDs.
#
# Inputs:
#   - Current network with imported pump rows (hw_pump) and links having
#     user_text_10 == 'Pump'
#
# Outputs:
#   - Console summary; new hw_pump rows in network
#
# UI vs Exchange: UI script.
#
# Hardening notes:
#   - Original used `pump_ro = new_pump_ro()` which is undefined. Replaced with
#     `pump_ro = net.new_row_object('hw_pump')` to match the documented intent.
#   - frozen_string_literal, timestamped logging, begin/rescue/ensure
#   - Per-link rescue; transaction commit on success, cancel on raise
# =============================================================================

def ts_log(msg)
  puts "[#{Time.now.strftime('%H:%M:%S')}] #{msg}"
end

begin
  ts_log "Starting Move/Copy Imported Pumps"

  net = WSApplication.current_network
  raise "Error: current network not found" if net.nil?

  nodes_roc = net.row_object_collection('_nodes')
  raise "Error: nodes not found" if nodes_roc.nil?
  links_roc = net.row_object_collection('_links')
  raise "Error: links not found" if links_roc.nil?
  subcatchments_roc = net.row_object_collection('_subcatchments')
  raise "Error: subcatchments not found" if subcatchments_roc.nil?
  pump_roc = net.row_object_collection('hw_pump')
  raise "Error: pump not found" if pump_roc.nil?

  nodes_ro = net.row_objects('_nodes')
  subcatchments_ro = net.row_objects('_subcatchments')
  links_ro = net.row_objects('_links')
  pump_ro_arr = net.row_objects('hw_pump')

  puts "Total number of nodes: #{nodes_ro.count}"
  puts "Total number of subcatchments: #{subcatchments_ro.count}"
  puts "Total number of links: #{links_ro.count}"
  puts "Total number of pumps: #{pump_ro_arr.count}"

  pump_links = links_ro.select { |l| l && (l.user_text_10 rescue nil) == 'Pump' }
  if pump_links.empty?
    puts "No pump links found."
    return
  end

  puts "Total number of pump links: #{pump_links.count}"
  net.transaction_begin
  begin
    pump_links.each_with_index do |link, idx|
      next if link.nil?
      begin
        puts "Pump Link #{idx + 1} - id=#{link.id}, us=#{link.us_node_id}, ds=#{link.ds_node_id}"
        new_pump = net.new_row_object('hw_pump')
        new_pump.us_node_id = link.us_node_id.to_s
        new_pump.ds_node_id = link.ds_node_id
        new_pump.id = link.id
        new_pump.write
      rescue => e
        ts_log "Failed creating pump for link #{link&.id}: #{e.message}"
      end
    end
    net.transaction_commit
    ts_log "Transaction committed"
  rescue => e
    net.transaction_cancel rescue nil
    raise
  end

rescue => e
  ts_log "FATAL: #{e.class}: #{e.message}"
  puts e.backtrace.first(5).join("\n") if e.backtrace
ensure
  ts_log "Move/Copy Imported Pumps finished"
end
