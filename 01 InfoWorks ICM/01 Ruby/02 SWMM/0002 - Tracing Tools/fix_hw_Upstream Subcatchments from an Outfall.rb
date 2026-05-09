# frozen_string_literal: true

# Purpose: Select upstream subcatchments from node with multilinks and hash acceleration
# Inputs: UI script; requires node selection
# Outputs: Selects upstream subcatchments, reports count and total area
# Type: UI script (runs in ICM context)
# Hardening: Begin/rescue/ensure, nil checks, visited tracking, hash-based lookup

begin
  net = WSApplication.current_network
  raise 'Network is not open' if net.nil?

  # Get all subcatchments from the network
  all_subs = net.row_objects('_subcatchments')

  # Create a hash variable for node->subcatchment mapping
  node_sub_hash_map = Hash.new { |h, k| h[k] = [] }

  # Get all nodes from the network
  all_nodes = net.row_objects('_nodes')

  # Pair subcatchments to nodes
  all_subs.each do |subb|
    if subb.node_id && !subb.node_id.empty?
      node_sub_hash_map[subb.node_id] << subb
    end
  end

  # Get all the selected rows in the _nodes collection
  roc = net.row_object_collection_selection('_nodes')
  raise 'No nodes selected' if roc.empty?

  # Create an empty array for unprocessed links
  unprocessedLinks = Array.new

  # Initialize counters
  total_subcatchments = 0
  total_area = 0.0

  roc.each do |ro|
    # Iterate through all the upstream links of the current row object
    ro.us_links.each do |l|
      if !l._seen
        unprocessedLinks << l
        l._seen = true
      end
    end

    # While there are still unprocessed links in the array
    while unprocessedLinks.size > 0
      # Take the first link in the array
      working = unprocessedLinks.shift
      working.selected = true

      # Get the upstream node of the current link
      workingUSNode = working.us_node

      # If the upstream node is not nil and has not been seen before
      if !workingUSNode.nil? && !workingUSNode._seen
        workingUSNode.selected = true

        # Get upstream subcatchments for this node
        node_sub_hash_map[workingUSNode.id].each do |sub|
          total_area += sub.total_area
          total_subcatchments += 1
          sub.selected = true
        end

        # Iterate through all upstream links and add to unprocessedLinks array
        workingUSNode.us_links.each do |l|
          if !l._seen
            unprocessedLinks << l
            l.selected = true
            l._seen = true
          end
        end
      end
    end
  end

  # Print results
  puts "Total number of found Subcatchments: #{total_subcatchments}"
  puts "Total area of found Subcatchments: #{total_area.round(4)}"

rescue => e
  puts "Error tracing upstream subcatchments: #{e.message}"
  WSApplication.message_box("Error: #{e.message}", 'OK', '!', false)
ensure
  # Cleanup _seen markers
  begin
    net&.row_objects('_links')&.each { |l| l._seen = false }
  rescue
    # Ignore cleanup errors
  end
end
