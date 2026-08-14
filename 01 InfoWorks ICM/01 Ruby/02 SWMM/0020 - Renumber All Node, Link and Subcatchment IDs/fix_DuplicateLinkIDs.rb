# frozen_string_literal: true

# =============================================================================
# fix_DuplicateLinkIDs.rb
# -----------------------------------------------------------------------------
# Purpose : Detect and report duplicate link ids across the various link
#           sub-tables in the current network.
# Inputs  : Current open network.
# Outputs : Console report of any duplicate ids found.
# UI / EX : UI script (uses current_network).
# Hardening:
#   - frozen_string_literal
#   - Header block, begin/rescue/ensure
#   - Validates network not nil and link collection not empty
#   - Nil-safe on `o.id` / `o.table`
#   - Returns final summary with duplicate count
#   - Preserves original behaviour
# =============================================================================

def ts
  Time.now.strftime('%Y-%m-%d %H:%M:%S')
end

begin
  puts "[#{ts}] Starting Duplicate Link ID detection."

  nw = WSApplication.current_network
  raise 'No current network is open.' if nw.nil?

  arr = nw.row_objects('_links')
  raise 'No links found.' if arr.nil? || arr.empty?

  links = {}
  duplicates = 0
  total = 0

  arr.each do |o|
    total += 1
    id = o.id
    next if id.nil?
    if links.key?(id)
      duplicates += 1
      puts "[#{ts}] Duplicate ID '#{id}' found in tables '#{o.table}' and '#{links[id]}'"
    else
      links[id] = o.table
    end
  end

  puts "[#{ts}] Scanned #{total} links - #{duplicates} duplicate id(s) reported."
rescue StandardError => e
  puts "[#{ts}] ERROR: #{e.message}"
  puts e.backtrace&.first(5)&.join("\n")
ensure
  puts "[#{ts}] Script finished."
end
