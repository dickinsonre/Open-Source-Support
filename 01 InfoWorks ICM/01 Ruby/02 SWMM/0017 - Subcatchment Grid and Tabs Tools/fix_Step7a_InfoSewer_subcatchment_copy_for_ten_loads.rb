# frozen_string_literal: true
# =============================================================================
# fix_Step7a_InfoSewer_subcatchment_copy_for_ten_loads.rb
# =============================================================================
# Purpose:
#   Hardened helper that copies each selected hw_subcatchment, suffixing the
#   subcatchment_id with "_copy". The original opens/commits a transaction
#   per copy; this version wraps the whole batch in one transaction for
#   speed and atomicity.
#
# Inputs:
#   - Current network with selected hw_subcatchment rows
#
# Outputs:
#   - One copy per selected subcatchment with the "_copy" suffix
#
# UI vs Exchange: UI script.
#
# Hardening notes:
#   - frozen_string_literal, timestamped logging
#   - begin/rescue/ensure with transaction rollback on raise
#   - Per-row rescue; nil-safe field iteration
# =============================================================================

def ts_log(msg)
  puts "[#{Time.now.strftime('%H:%M:%S')}] #{msg}"
end

begin
  ts_log "Starting copy-selected-subcatchments (_copy suffix)"

  net = WSApplication.current_network
  raise "No current network." if net.nil?

  net.transaction_begin
  begin
    copied = 0
    net.row_objects('hw_subcatchment').each do |sub|
      next if sub.nil?
      next unless (sub.selected? rescue false)
      begin
        new_obj = net.new_row_object('hw_subcatchment')
        new_obj['subcatchment_id'] = "#{sub['subcatchment_id']}_copy"
        new_obj.table_info.fields.each do |field|
          next if field.name == 'subcatchment_id'
          new_obj[field.name] = sub[field.name]
        end
        new_obj.write
        copied += 1
      rescue => e
        ts_log "Failed copying #{sub&.subcatchment_id}: #{e.message}"
      end
    end
    net.transaction_commit
    ts_log "Copied #{copied} subcatchment(s)"
  rescue => e
    net.transaction_cancel rescue nil
    raise
  end

rescue => e
  ts_log "FATAL: #{e.class}: #{e.message}"
  puts e.backtrace.first(5).join("\n") if e.backtrace
ensure
  ts_log "Copy-selected-subcatchments finished"
end
