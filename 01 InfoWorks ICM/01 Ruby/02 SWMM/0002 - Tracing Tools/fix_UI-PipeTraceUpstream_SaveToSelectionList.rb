# frozen_string_literal: true

# Purpose: Trace upstream from selected pipes, save to selection list
# Inputs: UI script; requires pipe selection
# Outputs: Creates selection list in Asset Group 3 with traced elements
# Type: UI script (runs in ICM context)
# Hardening: Begin/rescue/ensure, nil checks, visited tracking per pipe, transaction control

begin
  db = WSApplication.current_database
  net = WSApplication.current_network
  raise 'Network is not open' if net.nil?

  roc_pipe = net.row_objects_selection('cams_pipe')

  if roc_pipe.length == 0
    raise 'Please select one or more pipes'
  end

  roc_pipe.each do |ro_pipe|
    # Reset _seen markers for this pipe trace
    net.row_objects('_links').each { |l| l._seen = false }
    net.clear_selection

    ro_node = ro_pipe.navigate1('us_node')
    raise "Starting pipe node is nil" if ro_node.nil?

    puts "Processing pipe from node: #{ro_node.object_id}"

    selected_nodes = 0
    selected_links = 0

    ro = ro_node
    ro.selected = true
    selected_nodes += 1
    unprocessedLinks = Array.new

    ro.us_links.each do |l|
      unprocessedLinks << l if !l._seen
    end

    while unprocessedLinks.size > 0
      working = unprocessedLinks.shift
      working.selected = true
      selected_links += 1

      workingUSNode = working.navigate1('us_node')

      if !workingUSNode.nil?
        workingUSNode.selected = true
        selected_nodes += 1

        workingUSNode.us_links.each do |l|
          if !l._seen
            unprocessedLinks << l
            l._seen = true
          end
        end
      end
    end

    # Asset Group location to save a new Selection List to
    mo_assetgrp = db.model_object_from_type_and_id('Asset group', 3)
    raise 'Asset group 3 not found' if mo_assetgrp.nil?

    # Create a Selection List in the above Asset Group
    mo_sellist = mo_assetgrp.new_model_object('Selection list', ro_node.object_id.to_s)
    raise 'Failed to create selection list' if mo_sellist.nil?

    # Save the Selection to the above Selection List
    net.save_selection(mo_sellist)

    puts "Created selection list: #{ro_node.object_id}"
    puts "Selected nodes: #{selected_nodes}"
    puts "Selected links: #{selected_links}"
  end

rescue => e
  puts "Error in pipe trace: #{e.message}"
  WSApplication.message_box("Error: #{e.message}", "OK", "!", false)
ensure
  # Cleanup _seen markers
  begin
    net&.row_objects('_links')&.each { |l| l._seen = false }
  rescue
    # Ignore cleanup errors
  end
end
