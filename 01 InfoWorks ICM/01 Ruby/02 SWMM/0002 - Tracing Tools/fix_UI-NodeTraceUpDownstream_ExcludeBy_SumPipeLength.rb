# frozen_string_literal: true

# Purpose: Trace up/downstream from node, summing pipe lengths
# Inputs: UI script; requires 1 node selected; message box for direction choice
# Outputs: Selects traced path, reports node/link count and total length
# Type: UI script (runs in ICM context)
# Hardening: Begin/rescue/ensure, nil checks, visited tracking, user input validation

begin
  net = WSApplication.current_network
  raise 'Network is not open' if net.nil?

  roc = net.row_object_collection_selection('cams_manhole')

  if roc.length != 1
    raise 'Please select one manhole.'
  end

  upstream = nil
  response = WSApplication.message_box("Go upstream?\nYes = Upstream; No = Downstream", "YesNo", "?", true)
  raise 'User cancelled' if response.nil?

  upstream = response == "Yes"

  ro = roc[0]
  ro.selected = true
  selected_nodes = 1
  selected_links = 0
  links_length = 0.0
  unprocessedLinks = Array.new

  links = upstream ? ro.us_links : ro.ds_links

  links.each do |l|
    if !l._seen
      unprocessedLinks << l
      l._seen = true
    end
  end

  while unprocessedLinks.size > 0
    working = unprocessedLinks.shift
    working.selected = true
    selected_links += 1
    links_length += working.length

    workingNode = upstream ? working.us_node : working.ds_node

    if !workingNode.nil?
      workingNode.selected = true
      selected_nodes += 1

      links = upstream ? workingNode.us_links : workingNode.ds_links

      links.each do |l|
        if !l._seen
          unprocessedLinks << l
          l._seen = true
        end
      end
    end
  end

  puts "Trace #{upstream ? 'upstream' : 'downstream'} complete."
  puts "Selected nodes: #{selected_nodes}"
  puts "Selected links: #{selected_links}"
  puts "Selected links length: #{links_length.round(3)} (m)"

rescue => e
  puts "Error in trace: #{e.message}"
  WSApplication.message_box("Error: #{e.message}", 'OK', '!', false)
ensure
  # Cleanup _seen markers
  begin
    net&.row_object_collection('_links')&.each { |l| l._seen = false }
  rescue
    # Ignore cleanup errors
  end
end
