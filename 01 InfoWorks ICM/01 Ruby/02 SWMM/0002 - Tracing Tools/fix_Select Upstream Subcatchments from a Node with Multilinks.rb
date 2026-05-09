# frozen_string_literal: true

# Purpose: Select upstream subcatchments from node multilinks with hash acceleration
# Inputs: UI script; requires node selection
# Outputs: Selects all upstream subcatchments and accumulates area
# Type: UI script (runs in ICM context)
# Hardening: Begin/rescue/ensure, visited tracking, nil checks, hash-based lookup for performance

begin
  net = WSApplication.current_network
  raise 'Network is not open' if net.nil?

  # Get all subcatchments from the network and assign them to the variable all_subs
  all_subs = net.row_object_collection('hw_subcatchment')

  # Create an empty hash variable named node_sub_hash_map with default value
  node_sub_hash_map = Hash.new { |h, k| h[k] = [] }

  # Get all nodes from the network and assign them to the variable all_nodes
  all_nodes = net.row_object_collection('hw_node')

  # Pair subcatchments to appropriate hash keys (i.e. node id's) in the node_sub_hash_map
  all_subs.each do |subb|
    if subb.node_id && !subb.node_id.empty?
      node_sub_hash_map[subb.node_id] << subb
    else
      lateral_links = subb.lateral_links
      lateral_links.each do |link|
        node_sub_hash_map[link.node_id] << subb if link.node_id
      end
    end
  end

  # Get all the selected rows in the _nodes collection and assign them to the variable roc
  roc = net.row_object_collection_selection('_nodes')
  raise 'No nodes selected' if roc.empty?

  # Create an empty array named unprocessedLinks
  unprocessedLinks = Array.new

  # Initialize counters for results
  total_subcatchments = 0
  total_area = 0.0

  roc.each do |ro|
    # Iterate through all the upstream links of the current row object
    ro.us_links.each do |l|
      # if the link has not been seen before, add it to the unprocessedLinks array
      if !l._seen
        unprocessedLinks << l
        l._seen = true
      end
    end

    # While there are still unprocessed links in the array
    while unprocessedLinks.size > 0
      # take the first link in the array and assign it to the variable working
      working = unprocessedLinks.shift
      working.selected = true

      # get the upstream node of the current link
      workingUSNode = working.us_node

      # if the upstream node is not nil and has not been seen before
      if !workingUSNode.nil? && !workingUSNode._seen
        workingUSNode.selected = true

        # Now that hash is ready with node id's as key and upstream subcatchments as paired values
        node_sub_hash_map[workingUSNode.id].each do |sub|
          puts "Found Upstream Subcatchment #{sub.id} connected to Node #{workingUSNode.id}"
          total_area += sub.total_area
          total_subcatchments += 1
          sub.selected = true
        end

        # Iterate through all the upstream links of the current node and add them to the unprocessedLinks array
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

  puts "Upstream subcatchment trace complete."
  puts "Total subcatchments: #{total_subcatchments}, Total area: #{total_area.round(4)}"

rescue => e
  puts "Error tracing upstream subcatchments: #{e.message}"
  WSApplication.message_box("Error: #{e.message}", 'OK', '!', false)
ensure
  # Cleanup _seen markers
  begin
    net&.row_object_collection('_links')&.each { |l| l._seen = false }
  rescue
    # Ignore cleanup errors
  end
end
