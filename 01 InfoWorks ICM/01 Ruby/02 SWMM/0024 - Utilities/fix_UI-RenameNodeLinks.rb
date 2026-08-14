# frozen_string_literal: true

# =============================================================================
# fix_UI-RenameNodeLinks.rb
# -----------------------------------------------------------------------------
# Purpose : Auto-rename every selected node and selected link via the ICM
#           autoname rules.
# Inputs  : Current network with at least one selected node or link.
# Outputs : Renamed objects committed to the network.
# UI / EX : UI script (uses current_network and transaction_begin/commit).
# Hardening:
#   - frozen_string_literal
#   - Header block, begin/rescue/ensure
#   - Validates network not nil
#   - Warns if both selections are empty
#   - Wraps transaction in rescue with rollback on error
#   - Per-row rescue so one failure does not abort the run
#   - Timestamped progress logging
#   - Preserves original behaviour
# =============================================================================

def ts
  Time.now.strftime('%Y-%m-%d %H:%M:%S')
end

begin
  puts "[#{ts}] Starting Rename Node/Links via autoname."

  net = WSApplication.current_network
  raise 'No current network is open.' if net.nil?

  selected_nodes = net.row_objects_selection('_nodes')
  selected_links = net.row_objects_selection('_links')

  if (selected_nodes.nil? || selected_nodes.empty?) &&
     (selected_links.nil? || selected_links.empty?)
    raise 'Nothing is selected: select at least one node or link before running.'
  end

  net.transaction_begin
  begin
    n_count = 0
    l_count = 0

    (selected_nodes || []).each do |ro|
      begin
        ro.autoname
        ro.write
        n_count += 1
      rescue StandardError => ne
        puts "[#{ts}] ERROR autonaming node #{ro.id}: #{ne.message}"
      end
    end

    (selected_links || []).each do |ro|
      begin
        ro.autoname
        ro.write
        l_count += 1
      rescue StandardError => le
        puts "[#{ts}] ERROR autonaming link #{ro.id}: #{le.message}"
      end
    end

    net.transaction_commit
    puts "[#{ts}] Committed. Nodes renamed: #{n_count}, Links renamed: #{l_count}."
  rescue StandardError => txn_e
    net.transaction_rollback
    raise txn_e
  end
rescue StandardError => e
  puts "[#{ts}] ERROR: #{e.message}"
  puts e.backtrace&.first(5)&.join("\n")
ensure
  puts "[#{ts}] Script finished."
end
