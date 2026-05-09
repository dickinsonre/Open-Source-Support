# frozen_string_literal: true

# Purpose: Trace flow boundaries in InfoWorks networks with exclusion logic
# Inputs: UI script; requires 1 selected link
# Outputs: Selects trace links matching boundary conditions (area, status, type)
# Type: UI script (runs in ICM context)
# Hardening: Begin/rescue/ensure, visited tracking, nil checks on node navigation

# We can't access control directly (yet) so we rely on this hack setting tags on them
#
# @param network [WSOpenNetwork]
def find_boundary_links(network)
  network.clear_selection
  network.run_SQL('_links', "SELECT WHERE joined.pipe_closed = true")
  network.run_SQL('Valve', "SELECT WHERE (joined.mode IS NOT NULL) AND NOT (joined.mode = 'THV' AND joined.opening <> 0)")
  network.row_objects_selection('_links').each { |link| link._boundary = true }
  network.clear_selection
end

# Trace out from a link, given some boundary conditions. Selects links and nodes as we go.
#
# @param link [WSLink]
# @param conditions [Hash]
# @return [Array<WSLink>] returns an array of newly selected links
def trace_out_link(link, conditions)
  links = []

  # Find all connected links, stop at boundary nodes
  [link.us_node, link.ds_node].compact.each do |node|
    if conditions[:nodes].include?(node.table)
      node.selected = true if conditions[:trace_to_node]
      next
    else
      node.selected = true
      node.us_links.each { |l| links << l unless check_boundary_conditions(l, conditions) }
      node.ds_links.each { |l| links << l unless check_boundary_conditions(l, conditions) }
    end
  end

  links.each do |l|
    l._seen = true
    l.selected = true
  end

  links
end

# Check the boundary conditions for a link.
#
# @param link [WSLink]
# @param conditions [Hash]
# @return [Boolean] whether to reject the link i.e. true means this is a boundary
def check_boundary_conditions(link, conditions)
  return true if link._seen
  return true if link._boundary
  return true if conditions[:links].include?(link.table)
  return true if link['area'] != conditions[:area]
  false
end

begin
  # Open the current UI network
  network = WSApplication.current_network
  raise 'Network is not open' if network.nil?

  # Find the initial link we'll use to start the trace
  initial_link = network.row_objects_selection('_links').first
  raise 'No link(s) selected for trace' if initial_link.nil?

  # Boundary conditions
  find_boundary_links(network)
  conditions = {
    trace_to_node: true,
    nodes: ['wn_transfer_node', 'wn_fixed_head', 'wn_reservoir'],
    links: ['wn_pst', 'wn_meter'],
    area: initial_link['area']
  }

  # Trace
  initial_link.selected = true
  pending_links = [initial_link]
  link_count = 0

  until pending_links.empty?
    working_link = pending_links.shift
    traced = trace_out_link(working_link, conditions)
    pending_links = pending_links.concat(traced)
    link_count += traced.size
  end

  puts "Boundary trace completed. #{link_count} links traced."

rescue => e
  puts "Error in boundary trace: #{e.message}"
  WSApplication.message_box("Error: #{e.message}", 'OK', '!', false)
ensure
  # Cleanup if needed
end
