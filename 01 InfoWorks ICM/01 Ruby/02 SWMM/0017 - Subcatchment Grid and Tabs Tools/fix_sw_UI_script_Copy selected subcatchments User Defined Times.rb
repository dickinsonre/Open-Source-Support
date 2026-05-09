# frozen_string_literal: true
# =============================================================================
# fix_sw_UI_script_Copy selected subcatchments User Defined Times.rb
# =============================================================================
# Purpose:
#   Hardened helper that copies each selected sw_subcatchment N times,
#   suffixing the subcatchment_id with "_c_<n>". N defaults to 5; edit
#   `number_of_copies` to change.
#
# Inputs:  Current network with selected sw_subcatchment rows.
# Outputs: N copies per selected row.
# UI vs Exchange: UI script.
#
# Hardening notes:
#   - frozen_string_literal, timestamped logging
#   - begin/rescue/ensure with transaction rollback on raise
#   - Single transaction; per-row rescue
# =============================================================================

def ts_log(msg)
  puts "[#{Time.now.strftime('%H:%M:%S')}] #{msg}"
end

begin
  ts_log "Starting Copy selected subcatchments x N (sw_)"
  net = WSApplication.current_network
  raise "No current network." if net.nil?

  number_of_copies = 5
  total = 0
  net.transaction_begin
  begin
    net.row_objects('sw_subcatchment').each do |sub|
      next if sub.nil?
      next unless (sub.selected? rescue false)
      (1..number_of_copies).each do |n|
        begin
          new_obj = net.new_row_object('sw_subcatchment')
          new_obj['subcatchment_id'] = "#{sub['subcatchment_id']}_c_#{n}"
          new_obj.table_info.fields.each do |field|
            next if field.name == 'subcatchment_id'
            new_obj[field.name] = sub[field.name]
          end
          new_obj.write
          total += 1
        rescue => e
          ts_log "Failed copy #{sub&.subcatchment_id} #{n}: #{e.message}"
        end
      end
    end
    net.transaction_commit
    ts_log "Total new copies: #{total}"
  rescue => e
    net.transaction_cancel rescue nil
    raise
  end

rescue => e
  ts_log "FATAL: #{e.class}: #{e.message}"
  puts e.backtrace.first(5).join("\n") if e.backtrace
ensure
  ts_log "Copy x N (sw) finished"
end
