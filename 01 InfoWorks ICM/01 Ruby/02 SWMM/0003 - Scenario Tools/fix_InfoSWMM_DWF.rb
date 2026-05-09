# frozen_string_literal: true

# Purpose: Import InfoSWMM DWF (dry weather flow) data from CSV
# Inputs: UI script; user folder selection for dwf.csv
# Outputs: Updates base_flow and additional_dwf fields on nodes; reports totals
# Type: UI script (runs in ICM context)
# Hardening: Begin/rescue/ensure, file existence check, transaction control, nil checks

require 'csv'
require 'pathname'

def import_dwf(open_net)
  raise 'Network is not open' if open_net.nil?

  # Prompt the user to pick a folder
  val = WSApplication.prompt "Folder for an InfoSWMM DWF", [
    ['Pick the ISDB Folder','String',nil,nil,'FOLDER','ISDB Folder']], false

  raise 'Import cancelled by user' if val.nil? || val.empty?

  folder_path = val[0]
  raise 'No folder path provided' if folder_path.nil? || folder_path.empty?

  puts "Folder path: #{folder_path}"

  # Initialize an empty array to hold the hashes
  rows = []
  # Initialize a variable to store the total flow for all rows
  total_flow_all_rows = 0.0
  # Initialize a hash to store the count for each ID
  id_counts = Hash.new(0)

  scenario_csv = "#{folder_path}/dwf.csv"
  puts "\nScenario CSV: #{scenario_csv}"

  raise "DWF CSV not found" unless File.exist?(scenario_csv)

  # Headers to exclude
  exclude_headers = ["ALLOC_CODE","ITEM"]

  # Initialize a hash to store total and count for flow by id
  flow_stats = Hash.new { |h, k| h[k] = { total: 0, count: 0 } }

  # Create a hash that maps id to row object for nodes
  id_to_node = {}
  open_net.row_objects('_nodes').each { |ro| id_to_node[ro.node_id] = ro }

  # Read the CSV file
  File.open(scenario_csv, 'r') do |f|
    CSV.new(f, headers: true).each do |row|
      row_string = ""
      row.headers.each do |header|
        unless row[header].nil? || exclude_headers.include?(header)
          row_string += sprintf("%s: %s, ", header, row[header])
        end
      end

      # Add the row to the array as a hash
      rows << row.to_h

      # Update the count for the current ID
      id = row['ID']
      id_counts[id] += 1
      flow = row['VALUE'].to_f
      flow_stats[id][:total] += flow
      flow_stats[id][:count] += 1
      # Update the total flow for all rows
      total_flow_all_rows += flow

      # Update nodes
      ro = id_to_node[row["ID"]]
      if ro
        if id_counts[id] == 1
          ro.base_flow = row["VALUE"].to_f
        end
        ro.additional_dwf.each do |additional_dwf|
          additional_dwf.baseline = 0.0
        end
        ro.write
      end
    end
  end

  # Print the total flow for all rows and the count of all rows
  puts "\nTotal Flow Imported: #{total_flow_all_rows.round(4)}, Count: #{rows.size}"
  # Return the rows
  rows
end

begin
  # Access the current open network in the application
  cn = WSApplication.current_network
  raise 'Network is not open' if cn.nil?

  cn.transaction_begin
  rows = import_dwf(cn)
  cn.transaction_commit

  puts "\nDWF import complete."

rescue => e
  puts "Error importing DWF: #{e.message}"
  begin
    cn&.transaction_rollback
  rescue
    # Ignore rollback errors
  end
  WSApplication.message_box("Error: #{e.message}", 'OK', '!', false)
ensure
  # Cleanup if needed
end
