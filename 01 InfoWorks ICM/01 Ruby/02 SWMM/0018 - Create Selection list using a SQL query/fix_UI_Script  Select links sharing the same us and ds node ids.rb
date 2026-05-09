# frozen_string_literal: true

# =============================================================================
# fix_UI_Script  Select links sharing the same us and ds node ids.rb
# -----------------------------------------------------------------------------
# Purpose : Select all links that share the same upstream/downstream node-id
#           pair as another link (i.e. duplicate or parallel pipes).
# Inputs  : Current open network.
# Outputs : Updated selection on the network.
# UI / EX : UI script (uses current_network).
# Hardening:
#   - frozen_string_literal
#   - Header block, begin/rescue/ensure
#   - Validates network not nil
#   - Validates link collection not empty
#   - Skips links with nil us/ds node ids
#   - Timestamped progress logging
#   - Preserves original behaviour
# =============================================================================

def ts
  Time.now.strftime('%Y-%m-%d %H:%M:%S')
end

begin
  puts "[#{ts}] Starting Select Duplicate US/DS Links."

  net = WSApplication.current_network
  raise 'No current network is open.' if net.nil?

  net.clear_selection

  all_links = net.row_objects('_links')
  raise 'No link row objects found.' if all_links.nil?

  links_list_all = []
  all_links.each do |link|
    us = link.us_node_id
    ds = link.ds_node_id
    next if us.nil? || ds.nil?
    usds = "#{us}-#{ds}"
    links_list_all << [usds, link.id]
  end

  group_by_usds = links_list_all
                  .group_by { |usds, _id| usds }
                  .transform_values { |values| values.map { |_, id| id } }

  link_list_sel = group_by_usds.select { |_, ids| ids.length > 1 }.values.flatten

  selected = 0
  all_links.each do |link|
    if link_list_sel.include?(link.id)
      link.selected = true
      selected += 1
    end
  end

  puts "[#{ts}] Total links scanned: #{links_list_all.size}"
  puts "[#{ts}] Duplicate-pair groups : #{group_by_usds.count { |_, ids| ids.length > 1 }}"
  puts "[#{ts}] Links selected        : #{selected}"
rescue StandardError => e
  puts "[#{ts}] ERROR: #{e.message}"
  puts e.backtrace&.first(5)&.join("\n")
ensure
  puts "[#{ts}] Script finished."
end
