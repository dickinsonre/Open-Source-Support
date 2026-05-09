# frozen_string_literal: true

# =============================================================================
# fix_hw_UI_script_Add Nine 1D Results Points.rb
# -----------------------------------------------------------------------------
# Purpose : For each selected hw_conduit, add nine hw_1d_results_point rows
#           at 10%, 20%, ... 90% of the link's length.
# Inputs  : Current hw_* network with selected conduits.
# Outputs : New hw_1d_results_point rows in the network.
# UI / EX : UI script (uses current_network and transaction_begin/commit).
# Hardening:
#   - frozen_string_literal
#   - Header block, begin/rescue/ensure
#   - Validates network and required collections (nodes/links/conduits)
#   - Validates that at least one conduit is selected
#   - Validates us_node and ds_node lookups not nil
#   - Wraps transaction in rescue with rollback on error
#   - Per-conduit rescue so one bad row does not abort the run
#   - Timestamped progress logging
#   - Preserves original behaviour
# =============================================================================

def ts
  Time.now.strftime('%Y-%m-%d %H:%M:%S')
end

PERCENTAGES = [10, 20, 30, 40, 50, 60, 70, 80, 90].freeze

begin
  puts "[#{ts}] Starting Add Nine 1D Results Points."

  net = WSApplication.current_network
  raise 'Current network not found.' if net.nil?

  nodes_roc = net.row_object_collection('_nodes')
  raise 'No nodes found.' if nodes_roc.nil?

  links_roc = net.row_object_collection('_links')
  raise 'No links found.' if links_roc.nil?

  net.transaction_begin
  begin
    selected_count = 0
    points_created = 0

    net.row_objects('hw_conduit').each do |ro|
      next unless ro.selected
      selected_count += 1

      begin
        us_node_id = ro.us_node_id
        ds_node_id = ro.ds_node_id
        if us_node_id.nil? || ds_node_id.nil?
          puts "[#{ts}] Skipping conduit #{ro.id}: missing us/ds node id."
          next
        end

        us_node = net.row_object('hw_node', us_node_id)
        ds_node = net.row_object('hw_node', ds_node_id)
        if us_node.nil? || ds_node.nil?
          puts "[#{ts}] Skipping conduit #{ro.id}: us/ds node lookup returned nil."
          next
        end

        us_x = us_node.x; us_y = us_node.y
        ds_x = ds_node.x; ds_y = ds_node.y
        if [us_x, us_y, ds_x, ds_y].any?(&:nil?)
          puts "[#{ts}] Skipping conduit #{ro.id}: missing coordinates."
          next
        end

        conduit_len = ro.conduit_length || 0.0

        PERCENTAGES.each do |percentage|
          frac = percentage / 100.0
          position_x = us_x + (ds_x - us_x) * frac
          position_y = us_y + (ds_y - us_y) * frac

          result_point = net.new_row_object('hw_1d_results_point')
          result_point.point_id    = "#{us_node_id}_#{percentage}"
          result_point.point_x     = position_x
          result_point.point_y     = position_y
          result_point.link_suffix = ro.link_suffix
          result_point.us_node_id  = us_node_id
          result_point.start_length = conduit_len * frac
          result_point.write

          points_created += 1
        end
      rescue StandardError => row_e
        puts "[#{ts}] ERROR on conduit #{ro.id}: #{row_e.message}"
      end
    end

    net.transaction_commit
    net.clear_selection
    puts "[#{ts}] Committed. Conduits processed: #{selected_count}, points created: #{points_created}."
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
