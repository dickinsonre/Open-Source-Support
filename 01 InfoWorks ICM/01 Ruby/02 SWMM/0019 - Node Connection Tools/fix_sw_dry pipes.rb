# frozen_string_literal: true

# =============================================================================
# fix_sw_dry pipes.rb
# -----------------------------------------------------------------------------
# Purpose : Select 'dry pipes' in an ICM SWMM (sw_*) network: links that are
#           never reached by traversing downstream from any subcatchment
#           outlet node.
# Inputs  : Current open sw_* network with subcatchments and links.
# Outputs : Selection containing all dry links and their upstream nodes.
# UI / EX : UI script (uses current_network and ds_links graph traversal).
# Hardening:
#   - frozen_string_literal
#   - Header block, begin/rescue/ensure
#   - Validates network not nil and required collections not empty
#   - Nil-safety on each ds_node hop and on row_object lookups
#   - Resets _seen flag on links/nodes up front
#   - Timestamped progress logging and final count summary
# =============================================================================

def ts
  Time.now.strftime('%Y-%m-%d %H:%M:%S')
end

begin
  puts "[#{ts}] Starting sw_ dry-pipes detection."

  net = WSApplication.current_network
  raise 'No current network is open.' if net.nil?

  net.clear_selection

  subs = net.row_object_collection('_subcatchments')
  raise 'No subcatchments found.' if subs.nil? || subs.empty?

  all_links = net.row_object_collection('_links')
  raise 'No links found.' if all_links.nil? || all_links.empty?

  all_nodes = net.row_object_collection('_nodes')

  all_links.each { |l| l._seen = false }
  all_nodes.each { |n| n._seen = false } if all_nodes

  unprocessed_links = []
  subs.each do |sub|
    nid = sub.outlet_id
    next if nid.nil? || nid.to_s.empty?
    begin
      nd = net.row_object('sw_node', nid)
    rescue StandardError
      nd = nil
    end
    next if nd.nil?
    nd.ds_links&.each { |l| unprocessed_links << l }
  end

  while unprocessed_links.size > 0
    working = unprocessed_links.shift
    next if working.nil?
    working._seen = true
    ds_node = working.ds_node
    if !ds_node.nil? && !ds_node._seen
      ds_node._seen = true
      ds_node.ds_links&.each { |b| unprocessed_links << b }
    end
  end

  dry_links = 0
  all_links.each do |d|
    next if d._seen
    d.selected = true
    dry_links += 1
    if d.us_node
      d.us_node.selected = true
      puts "[#{ts}] Selected dry-pipe US node: #{d.us_node.id}"
    end
  end

  puts "[#{ts}] Dry pipes selected: #{dry_links}"
rescue StandardError => e
  puts "[#{ts}] ERROR: #{e.message}"
  puts e.backtrace&.first(5)&.join("\n")
ensure
  puts "[#{ts}] Script finished."
end
