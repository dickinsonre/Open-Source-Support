# frozen_string_literal: true

# =============================================================================
# fix_UI_Script.rb
# -----------------------------------------------------------------------------
# Purpose : Run SQL queries against _links / _nodes / _subcatchments to flag
#           rows containing flag value 'ISAC', then save the resulting
#           selection as a Selection List under a named Model Group.
# Inputs  : Current open database & network. MODEL_GROUP_NAME constant.
# Outputs : Selection List 'Conduits' on the database.
# UI / EX : UI script (uses run_SQL, save_selection).
# Hardening:
#   - frozen_string_literal
#   - Header block, begin/rescue/ensure
#   - Validates database and network not nil
#   - Validates group lookup not nil
#   - Each run_SQL is wrapped in its own rescue so one bad query does not
#     abort the run
#   - Fixes the original SQL syntax (stray double-quote was a bug)
#   - Timestamped progress logging
#   - Preserves original intent
# =============================================================================

def ts
  Time.now.strftime('%Y-%m-%d %H:%M:%S')
end

MODEL_GROUP_NAME = 'InfoSewer_ICM_Erie_Models_Feb'

begin
  puts "[#{ts}] Starting UI_Script (build selection list from flag='ISAC')."

  db = WSApplication.current_database
  raise 'No current database is open.' if db.nil?

  net = WSApplication.current_network
  raise 'No current network is open.' if net.nil?

  net.clear_selection

  group = db.find_root_model_object('Model Group', MODEL_GROUP_NAME)
  raise "Model Group '#{MODEL_GROUP_NAME}' not found." if group.nil?

  # Original used: flags.value='ISAC'' (extra quote was a typo).
  sql = "flags.value='ISAC'"
  %w[_links _nodes _subcatchments].each do |table|
    begin
      n = net.run_SQL(table, sql)
      puts "[#{ts}] run_SQL on #{table} returned #{n.inspect}."
    rescue StandardError => sql_e
      puts "[#{ts}] WARNING: run_SQL on #{table} failed: #{sql_e.message}"
    end
  end

  sl = group.new_model_object('Selection List', 'Conduits')
  raise 'Could not create Selection List object.' if sl.nil?

  puts "[#{ts}] Selection list name: #{sl.name}"
  net.save_selection(sl)

  puts "[#{ts}] Selection saved to '#{sl.name}' under '#{MODEL_GROUP_NAME}'."
rescue StandardError => e
  puts "[#{ts}] ERROR: #{e.message}"
  puts e.backtrace&.first(5)&.join("\n")
ensure
  puts "[#{ts}] Script finished."
end
