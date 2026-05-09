# frozen_string_literal: true

# =============================================================================
# fix_UI-CreateSelectionList.rb
# -----------------------------------------------------------------------------
# Purpose : Save the current network selection (nodes + links) as a Selection
#           List model object on the database under a chosen Model Group.
# Inputs  : Current open database & network. Hard-coded model group name
#           (edit MODEL_GROUP_NAME constant below).
# Outputs : New Selection List(s) under the selected Model Group.
# UI / EX : UI script (ICM UI - uses current_database / current_network).
# Hardening:
#   - frozen_string_literal
#   - Header block, begin/rescue/ensure
#   - Validates database, network and target group are not nil
#   - Validates that a selection actually exists before saving
#   - Timestamped progress logging
#   - Preserves original behaviour (creates two Selection Lists "Anode" and
#     "Alink" under the named group)
# =============================================================================

def ts
  Time.now.strftime('%Y-%m-%d %H:%M:%S')
end

MODEL_GROUP_NAME = 'yarra'  # << edit to your group name or numeric id

begin
  puts "[#{ts}] Starting Create Selection List script."

  db  = WSApplication.current_database
  raise 'No current database is open.' if db.nil?

  net = WSApplication.current_network
  raise 'No current network is open.' if net.nil?

  # Try the original lookup style first, then fall back to find_root_model_object
  group = nil
  begin
    group = db.model_object_from_type_and_id('Model Group', MODEL_GROUP_NAME)
  rescue StandardError
    group = nil
  end
  group ||= db.find_root_model_object('Model Group', MODEL_GROUP_NAME)
  raise "Model Group '#{MODEL_GROUP_NAME}' not found." if group.nil?

  # Validate that something is selected on the network
  selected_nodes = 0
  selected_links = 0
  begin
    net.row_objects('_nodes').each { |n| selected_nodes += 1 if n.selected }
    net.row_objects('_links').each { |l| selected_links += 1 if l.selected }
  rescue StandardError => sel_e
    puts "[#{ts}] Warning while counting selection: #{sel_e.message}"
  end

  if selected_nodes.zero? && selected_links.zero?
    puts "[#{ts}] WARNING: No nodes or links are selected. Selection lists will be empty."
  end

  sl_node = group.new_model_object('Selection List', 'Anode')
  sl_link = group.new_model_object('Selection List', 'Alink')
  raise 'Could not create Selection List objects.' if sl_node.nil? || sl_link.nil?

  net.save_selection(sl_node)
  net.save_selection(sl_link)

  puts "[#{ts}] Selection saved into '#{sl_node.name}' and '#{sl_link.name}' under '#{MODEL_GROUP_NAME}'."
  puts "[#{ts}] Selected counts -> nodes=#{selected_nodes}, links=#{selected_links}."

rescue StandardError => e
  puts "[#{ts}] ERROR: #{e.message}"
  puts e.backtrace&.first(5)&.join("\n")
ensure
  puts "[#{ts}] Script finished."
end
