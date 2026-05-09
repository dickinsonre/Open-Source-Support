# frozen_string_literal: true

# Purpose: Dijkstra quicktrace for SWMM networks with link length tracking
# Inputs: UI script; requires 2 selected nodes
# Outputs: Selects shortest path; reports nodes/links found and total length
# Type: UI script (runs in ICM context)
# Hardening: Begin/rescue/ensure, input validation, nil checks

class QuickTrace
  def initialize
    @net = WSApplication.current_network
    raise 'Network is not open' if @net.nil?
  end

  def process_node(n)
    working = Array.new
    working_hash = Hash.new
    calculated = Array.new
    calculated_hash = Hash.new
    n._val = 0.0
    n._from = nil
    n._link = nil
    @total_length_of_links = 0.0

    working << n
    working_hash[n.id] = 0

    while working.size > 0
      min = nil
      min_index = -1

      (0...working.size).each do |i|
        if min.nil? || working[i]._val < min
          min = working[i]._val
          min_index = i
        end
      end

      if min_index < 0
        puts "Index error in working array"
        return nil
      end

      current = working.delete_at(min_index)
      return current if current.id == @dest

      working_hash.delete current.id
      calculated << current
      calculated_hash[current.id] = 0

      (0..1).each do |direction|
        links = (direction == 0) ? current.ds_links : current.us_links

        links.each do |l|
          node = (direction == 0) ? l.ds_node : l.us_node

          if !node.nil? && !calculated_hash.has_key?(node.id)
            if working_hash.has_key? node.id
              index = -1
              (0...working.size).each do |i|
                if working[i].id == node.id
                  index = i
                  break
                end
              end
              raise "Working object #{node.id} in hash but not array" if index == -1
            else
              working << node
              working_hash[node.id] = 0
              index = working.size - 1
            end

            if l.length > 0.0
              working[index]._val = current._val + l.length
              @total_length_of_links += l.length
            else
              working[index]._val = current._val + 5
            end

            working[index]._from = current
            working[index]._link = l
          end
        end
      end
    end

    nil
  end

  def doit
    nodes = @net.row_objects_selection('sw_node')

    if nodes.size != 2
      raise 'Please select two nodes for the trace.'
    end

    @dest = nodes[1].id
    found = process_node(nodes[0])

    if found.nil?
      raise 'Target node not reachable from start node'
    end

    total_nodes_found = 0
    total_links_found = 0

    while !found.nil?
      found.selected = true
      if !found._link.nil?
        found._link.selected = true
        total_links_found += 1
      end
      total_nodes_found += 1
      found = found._from
    end

    puts "Trace completed. You should see a red line trace."
    puts "Total nodes found: #{total_nodes_found}"
    puts "Total links found: #{total_links_found}"
    puts "Total length of links: #{@total_length_of_links.round(2)}"
  end
end

begin
  d = QuickTrace.new
  d.doit
rescue => e
  puts "Error in quicktrace: #{e.message}"
  WSApplication.message_box("Error: #{e.message}", 'OK', '!', false)
ensure
  # Cleanup if needed
end
