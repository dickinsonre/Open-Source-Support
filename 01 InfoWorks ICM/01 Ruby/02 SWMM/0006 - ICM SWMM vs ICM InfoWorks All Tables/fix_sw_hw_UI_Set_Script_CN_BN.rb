# frozen_string_literal: true
# ---------------------------------------------------------------------------
# fix_sw_hw_UI_Set_Script_CN_BN.rb
#
# Purpose : Cross-product helper.  Reads capacity/gradient on hw_conduit rows
#           in the background (InfoWorks) network, then writes them onto the
#           sw_conduit rows in the current (SWMM) network as user_number_9
#           (gradient) and user_number_10 (capacity).
# Inputs  : - Background network (ICM InfoWorks) with hw_conduit rows.
#           - Current network (ICM SWMM) with sw_conduit rows.
# Outputs : Updated user_number_9 and user_number_10 on sw_conduit.
# Type    : UI script.
# Hardening:
#   * frozen_string_literal pragma
#   * Validates both networks not nil
#   * begin/rescue/ensure with rollback on transaction error
#   * Nil-safe attribute access
#   * Timestamped logging
# ---------------------------------------------------------------------------

def log(msg)
  puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] #{msg}"
end

begin
  bn = WSApplication.background_network
  raise 'No background network. Set an InfoWorks network as background.' if bn.nil?

  cn = WSApplication.current_network
  raise 'No current network. Open a SWMM network.' if cn.nil?

  bn.clear_selection
  cn.clear_selection

  link_properties = {}
  log 'Reading hw_conduit capacity & gradient from background network...'
  bn.row_objects('hw_conduit').each do |rohw|
    next if rohw.nil?
    next unless rohw.capacity && rohw.gradient
    link_properties[rohw.asset_id] = { capacity: rohw.capacity, gradient: rohw.gradient }
  end
  log "Loaded #{link_properties.size} hw_conduit rows."

  rows_written = 0
  in_transaction = false
  begin
    cn.transaction_begin
    in_transaction = true

    cn.row_objects('sw_conduit').each do |rosw|
      next if rosw.nil?
      props = link_properties[rosw.id]
      next unless props
      rosw.user_number_9  = props[:gradient]
      rosw.user_number_10 = props[:capacity]
      rosw.write
      rows_written += 1
    end

    cn.transaction_commit
    in_transaction = false
  rescue StandardError => txn_err
    log "Transaction error: #{txn_err.message}"
    if in_transaction
      begin
        cn.transaction_rollback
      rescue StandardError
        # ignore
      end
    end
    raise
  end

  puts "Number of rows written to ICM SWMM: #{rows_written}"
rescue StandardError => e
  log "Aborted: #{e.message}"
ensure
  log 'fix_sw_hw_UI_Set_Script_CN_BN.rb finished.'
end
