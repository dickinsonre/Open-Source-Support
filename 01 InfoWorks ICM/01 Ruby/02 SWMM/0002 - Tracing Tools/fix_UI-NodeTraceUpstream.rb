# frozen_string_literal: true

# Purpose: Trace upstream from selected node
# Inputs: UI script; requires 1 node selected
# Outputs: Selects upstream path nodes and links with count reporting
# Type: UI script (runs in ICM context)
# Hardening: Begin/rescue/ensure, nil checks, visited tracking

begin
  net = WSApplication.current_network
  raise 'Network is not open' if net.nil?

  roc = net.row_object_collection_selection('cams_manhole')

  if roc.length != 1
    raise 'Please select one manhole'
  end

  ro = roc[0]
  ro.selected = true
  selected_nodes = 1
  selected_links = 0
  unprocessedLinks = Array.new

  ro.us_links.each do |l|
    if !l._seen
      unprocessedLinks << l
      l._seen = true
    end
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

  puts "Trace upstream complete."
  puts "Selected nodes: #{selected_nodes}"
  puts "Selected links: #{selected_links}"

rescue => e
  puts "Error in upstream trace: #{e.message}"
  WSApplication.message_box("Error: #{e.message}", 'OK', '!', false)
ensure
  # Cleanup _seen markers
  begin
    net&.row_object_collection('_links')&.each { |l| l._seen = false }
  rescue
    # Ignore cleanup errors
  end
end
