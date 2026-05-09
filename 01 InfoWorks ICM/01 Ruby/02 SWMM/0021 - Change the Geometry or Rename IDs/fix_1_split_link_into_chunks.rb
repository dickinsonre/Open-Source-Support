# frozen_string_literal: true

# =============================================================================
# fix_1_split_link_into_chunks.rb
# -----------------------------------------------------------------------------
# Purpose : Split each selected wn_pipe into evenly-sized chunks of length
#           DEFAULT_CHUNK_SIZE using helpers in spatial.rb.
# Inputs  : Current open network with selected wn_pipe rows.
# Outputs : New nodes inserted along each link; original link is split.
# UI / EX : UI script (uses current_network and transaction_begin/commit).
# Hardening:
#   - frozen_string_literal
#   - Header block, begin/rescue/ensure
#   - Validates network not nil and selection non-empty
#   - Wraps transaction_begin in rescue with transaction_rollback
#   - Per-link rescue so a single failure does not abort the run
#   - Timestamped progress logging
#   - Preserves original behaviour
# =============================================================================

require_relative 'spatial'

def ts
  Time.now.strftime('%Y-%m-%d %H:%M:%S')
end

DEFAULT_CHUNK_SIZE = 10.0

begin
  puts "[#{ts}] Starting Split Link Into Chunks (size=#{DEFAULT_CHUNK_SIZE})."

  size = DEFAULT_CHUNK_SIZE
  # size = WSApplication.input_box('Specify a chunk size', 'Split Lines into Chunks', DEFAULT_CHUNK_SIZE.to_s)
  # raise 'Cancelled by user.' if size.nil?
  # size = size.to_f

  raise 'Chunk size must be > 0.' unless size.is_a?(Numeric) && size.positive?

  network = WSApplication.current_network
  raise 'No current network is open.' if network.nil?

  selection = network.row_objects_selection('wn_pipe')
  raise 'No wn_pipe rows are selected.' if selection.nil? || selection.empty?

  network.transaction_begin
  begin
    processed = 0
    selection.each do |link|
      bends = link['bends']
      if bends.nil? || bends.length < 4
        puts "[#{ts}] Skipping link #{link.id}: bends array < 2 vertices."
        next
      end

      begin
        InnoSpatial.split_link_into_chunks(network, link, size)
        processed += 1
      rescue StandardError => link_e
        puts "[#{ts}] ERROR splitting link #{link.id}: #{link_e.message}"
      end
    end
    network.transaction_commit
    puts "[#{ts}] Transaction committed. Links processed: #{processed}."
  rescue StandardError => txn_e
    network.transaction_rollback
    raise txn_e
  end
rescue StandardError => e
  puts "[#{ts}] FATAL: #{e.message}"
  puts e.backtrace&.first(5)&.join("\n")
ensure
  puts "[#{ts}] Script finished."
end
