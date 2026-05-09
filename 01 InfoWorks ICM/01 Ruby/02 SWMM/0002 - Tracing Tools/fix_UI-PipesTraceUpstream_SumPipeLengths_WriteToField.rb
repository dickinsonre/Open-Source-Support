# frozen_string_literal: true

# Purpose: Trace upstream from pipes, sum lengths, write to user_number_1 field
# Inputs: UI script; requires pipe selection
# Outputs: Updates user_number_1 field on each starting pipe; reports counts and length
# Type: UI script (runs in ICM context)
# Hardening: Begin/rescue/ensure, nil checks, visited tracking, transaction management

begin
  db = WSApplication.current_database
  net = WSApplication.current_network
  raise 'Network is not open' if net.nil?

  roc_pipe = net.row_objects_selection('cams_pipe')

  if roc_pipe.length == 0
    WSApplication.message_box "Please select one or more Pipes\nThen re-run the trace script", "OK", "Information", false
  else
    roc_pipe.each do |ro_pipe|
      links_length = 0.0
      puts "\nTracing from: #{ro_pipe.us_node_id}.#{ro_pipe.ds_node_id}.#{ro_pipe.link_suffix}"

      # Reset _seen markers for this pipe trace
      net.row_objects('_links').each { |l| l._seen = false }

      links_length += ro_pipe.length

      ro_node = ro_pipe.navigate1('us_node')
      raise "Starting pipe node is nil" if ro_node.nil?

      selected_nodes = 0
      selected_links = 0

      if ro_node
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
          links_length += working.length

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
      end

      net.transaction_begin
      ro_pipe.user_number_1 = links_length
      ro_pipe.write
      net.transaction_commit

      puts "Selected nodes: #{selected_nodes}"
      puts "Selected links: #{selected_links}"
      links_length_r = links_length.round(3).to_s
      puts "Selected links length: #{links_length_r} (m)"
      puts "Wrote length to user_number_1"
    end
  end

rescue => e
  puts "Error in pipe trace: #{e.message}"
  begin
    net&.transaction_rollback
  rescue
    # Ignore rollback errors
  end
  WSApplication.message_box("Error: #{e.message}", "OK", "!", false)
ensure
  # Cleanup _seen markers
  begin
    net&.row_objects('_links')&.each { |l| l._seen = false }
  rescue
    # Ignore cleanup errors
  end
end
