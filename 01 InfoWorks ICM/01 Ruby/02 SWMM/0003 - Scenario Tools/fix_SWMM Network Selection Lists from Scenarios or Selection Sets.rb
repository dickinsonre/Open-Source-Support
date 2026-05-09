# frozen_string_literal: true

# Purpose: Create selection lists for active SWMM elements from scenario folders
# Inputs: UI script; user folder selection for scenario/selection set data
# Outputs: Creates selection lists in parent model group; reports completion
# Type: UI script (runs in ICM context)
# Hardening: Begin/rescue/ensure, file checks, transaction control, error handling

require 'csv'
require 'pathname'

# Method to import active nodes (anode) and links (alink) from CSV files
def import_anode_and_alink(open_net, parent_object)
  raise 'Network is not open' if open_net.nil?
  raise 'Parent object is nil' if parent_object.nil?

  # Prompt the user to select the Scenario folder
  val = WSApplication.prompt("Active or Selected Elements", [
    ['Pick the Scenario or Select/SS Folder', 'String', nil, nil, 'FOLDER', 'Scenario/Selection Folder']
  ], false)

  # Check if the user clicked 'Cancel'
  raise "Import process was canceled by user" if val.nil? || val.empty?

  folder_path = val[0]

  # Check if folder path is provided
  raise "Invalid folder path provided" if folder_path.nil? || folder_path.empty?

  # Hashes to store links, nodes, and subcatchments
  id_to_link = {}
  id_to_node = {}
  id_to_subcatchment = {}

  # Populate the hashes with network objects
  open_net.row_objects('_links').each { |ro| id_to_link[ro.id] = ro }
  open_net.row_objects('_nodes').each { |ro| id_to_node[ro.node_id] = ro }
  open_net.row_objects('_subcatchments').each { |ro| id_to_subcatchment[ro.subcatchment_id] = ro }

  # Clear any existing selection in the network
  open_net.clear_selection

  # Iterate over all subdirectories in the selected folder
  Pathname.new(folder_path).children.select(&:directory?).each do |dir|
    # Clear selection before processing each subdirectory
    open_net.clear_selection

    # Create a new selection list for each subdirectory
    selection_set = Pathname.new(dir).basename.to_s
    sl = parent_object.new_model_object 'Selection List', selection_set
    raise "Failed to create selection list for #{selection_set}" if sl.nil?

    ['anode.csv', 'alink.csv'].each do |filename|
      csv_path = "#{dir}/#{filename}"

      # Check if the CSV file exists
      next unless File.exist?(csv_path)

      # Array to hold the CSV rows
      rows = []

      # Read the CSV file and store rows in the array
      File.open(csv_path, 'r') do |f|
        CSV.new(f, headers: true).each do |row|
          row_hash = row.to_h
          # Add directory and source to the hash
          row_hash["dir_source"] = File.basename(dir.to_s) + "_" + File.basename(filename, '.*')
          rows << row_hash

          # Add links from alink.csv
          if filename == 'alink.csv' && ro = id_to_link[row["ID"]]
            ro.selected = true
            ro.write
          end

          # Add nodes from anode.csv
          if filename == 'anode.csv' && ro = id_to_node[row["ID"]]
            ro.selected = true
            ro.write
          end

          # Add subcatchments (assumed to be same as nodes)
          if ro = id_to_subcatchment[row["ID"]]
            ro.selected = true
            ro.write
          end
        end
      end
    end

    # Save the selection list
    open_net.save_selection(sl)
    puts "Created selection list: #{sl.name}\n"
  end

  true
end

begin
  # Access the current network
  open_net = WSApplication.current_network
  raise 'Network is not open' if open_net.nil?

  # Fetch the parent object
  db = WSApplication.current_database
  current_network_object = open_net.model_object
  parent_id = current_network_object.parent_id

  # Attempt to find the parent object assuming it's a 'Model Group'
  # If unsuccessful, assume the parent object is a 'Model Network' and find its parent 'Model Group'
  begin
    parent_object = db.model_object_from_type_and_id 'Model Group', parent_id
  rescue
    parent_object = db.model_object_from_type_and_id 'Model Network', parent_id
    raise 'Network parent is nil' if parent_object.nil?

    parent_id = parent_object.parent_id
    parent_object = db.model_object_from_type_and_id 'Model Group', parent_id
  end

  raise 'Parent object is nil' if parent_object.nil?

  # Start a transaction and call the function to create the selection list
  open_net.transaction_begin
  if import_anode_and_alink(open_net, parent_object)
    # Print completion message
    puts "\nNote: If the selection list is empty for a scenario, all nodes and links may be active in the InfoSewer/InfoSWMM Scenario."
    puts "\nFinished the creation of ICM Selection Lists from InfoSewer or InfoSWMM Scenarios or Selection Sets."
    puts "\nRefresh the database to view the new selection lists in the database tree."
  end
  open_net.transaction_commit

rescue => e
  puts "Error importing active elements: #{e.message}"
  begin
    open_net&.transaction_rollback
  rescue
    # Ignore rollback errors
  end
  WSApplication.message_box("Error: #{e.message}", 'OK', '!', false)
ensure
  # Clear any existing selection in the network
  begin
    open_net&.clear_selection
  rescue
    # Ignore cleanup errors
  end
end
