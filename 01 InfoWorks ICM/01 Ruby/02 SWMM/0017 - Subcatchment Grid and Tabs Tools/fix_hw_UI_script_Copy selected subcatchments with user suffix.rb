# frozen_string_literal: true
# =============================================================================
# fix_hw_UI_script_Copy selected subcatchments with user suffix.rb
# =============================================================================
# Purpose:
#   Hardened helper that copies each selected hw_subcatchment once per suffix
#   in the suffixes list (defaults: Horton / GreenAmpt / Constant), naming
#   each copy "<original_id>_<suffix>".
#
# Inputs:  Current network with selected hw_subcatchment rows.
# Outputs: One copy per (selection x suffix).
# UI vs Exchange: UI script.
#
# Hardening notes:
#   - frozen_string_literal, timestamped logging
#   - begin/rescue/ensure with transaction rollback on raise
#   - Single transaction (instead of one per copy)
#   - Per-row rescue; nil-safe field iteration
# =============================================================================

def ts_log(msg)
  puts "[#{Time.now.strftime('%H:%M:%S')}] #{msg}"
end

begin
  ts_log "Starting Copy selected subcatchments by suffix (hw_)"
  net = WSApplication.current_network
  raise "No current network." if net.nil?

  suffixes = ["Horton", "GreenAmpt", "Constant"]
  original_selected_count = 0
  new_subcatchments_added = 0

  net.transaction_begin
  begin
    net.row_objects('hw_subcatchment').each do |sub|
      next if sub.nil?
      next unless (sub.selected? rescue false)
      original_selected_count += 1
      suffixes.each do |suffix|
        begin
          new_obj = net.new_row_object('hw_subcatchment')
          new_obj['subcatchment_id'] = "#{sub['subcatchment_id']}_#{suffix}"
          new_obj.table_info.fields.each do |field|
            next if field.name == 'subcatchment_id'
            new_obj[field.name] = sub[field.name]
          end
          new_obj.write
          new_subcatchments_added += 1
        rescue => e
          ts_log "Failed copy #{sub&.subcatchment_id} _#{suffix}: #{e.message}"
        end
      end
    end
    net.transaction_commit
    puts "Number of original selected subcatchments: #{original_selected_count}"
    puts "Number of new subcatchments added: #{new_subcatchments_added}"
  rescue => e
    net.transaction_cancel rescue nil
    raise
  end

rescue => e
  ts_log "FATAL: #{e.class}: #{e.message}"
  puts e.backtrace.first(5).join("\n") if e.backtrace
ensure
  ts_log "Copy by suffix (hw) finished"
end
