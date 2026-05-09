# frozen_string_literal: true

# Purpose: Calculate total subcatchment area upstream from each selected node
# Inputs: UI script; requires node selection
# Outputs: For each node: prints downstream nodes with their subcatchment areas
# Type: UI script (runs in ICM context)
# Hardening: Begin/rescue/ensure, nil checks, visited tracking, duplicate traversal prevention

begin
  net = WSApplication.current_network
  raise 'Network is not open' if net.nil?

  net.clear_selection
  $ro = net.row_object('hw_node', '44628801')
  raise 'Starting node not found' if $ro.nil?

  $unprocessed_links = Array.new
  $seen_objects = Array.new

  def mark(object)
    object.selected = true
    object._seen = true
    $seen_objects << object
  end

  def unsee_all
    $seen_objects.each { |object| object._seen = false }
    $seen_objects = Array.new
  end

  def unprocessed_links(node)
    node.us_links.each do |link|
      mark(link) if !link._seen
      $unprocessed_links << link
    end
  end

  def tot_sub_area(object)
    tot_sub_area = 0
    subs = object.navigate('subcatchments')
    subs&.each do |subs|
      tot_sub_area += subs.total_area
      mark(subs)
    end
    tot_sub_area
  end

  def trace_us(node)
    mark(node)
    total_area = tot_sub_area(node)
    unprocessed_links(node)
    nodes_us = Array.new
    nodes_us << node

    while $unprocessed_links.size > 0
      working_link = $unprocessed_links.shift
      working_node = working_link.us_node
      total_area += tot_sub_area(working_link) if !working_link.nil?

      if !working_node.nil? && !working_node._seen
        total_area += tot_sub_area(working_node)
        unprocessed_links(working_node)
        mark(working_node)
        nodes_us << working_node
      end
    end

    unsee_all
    [nodes_us, total_area]
  end

  result = trace_us($ro)
  result[0].each do |node|
    area = trace_us(node)[1]
    puts "%s: %s" % [node.node_id, area.round(3)]
  end

  puts "Subcatchment area trace complete."

rescue => e
  puts "Error in subcatchment trace: #{e.message}"
  WSApplication.message_box("Error: #{e.message}", 'OK', '!', false)
ensure
  # Cleanup if needed
  begin
    $seen_objects = Array.new if defined?($seen_objects)
  rescue
    # Ignore cleanup errors
  end
end
