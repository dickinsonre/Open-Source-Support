# frozen_string_literal: true

# Purpose: Trace up/downstream from node with invert level exclusion
# Inputs: UI script; requires 1 node selected; message box for direction choice
# Outputs: Selects traced path excluding links below invert level 15
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
  unprocessedLinks = Array.new

  links = upstream ? ro.us_links : ro.ds_links

  links.each do |l|
    if !l._seen
      unprocessedLinks << l if l.us_invert > 15
      l._seen = true
    end
  end

  while unprocessedLinks.size > 0
    working = unprocessedLinks.shift
    working.selected = true

    workingNode = upstream ? working.us_node : working.ds_node

    if !workingNode.nil?
      workingNode.selected = true
      links = upstream ? workingNode.us_links : workingNode.ds_links

      links.each do |l|
        if !l._seen
          unprocessedLinks << l if l.us_invert > 15
          l._seen = true
        end
      end
    end
  end

  puts "Trace #{upstream ? 'upstream' : 'downstream'} by invert level complete."

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
