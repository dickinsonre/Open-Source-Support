# frozen_string_literal: true
# ---------------------------------------------------------------------------
# fix_check_fields.rb
#
# Purpose : Diagnostic - lists all methods and (optionally) the .fields
#           output of the first sw_conduit object in the current network so
#           you can map ICM API attribute names to your scripts.
# Inputs  : Active current_network with at least one sw_conduit row.
# Outputs : Console diagnostic.
# Type    : UI script.
# Hardening:
#   * frozen_string_literal pragma
#   * Validates current_network not nil
#   * Per-call rescue around .fields and .methods
#   * Timestamped logging
# ---------------------------------------------------------------------------

def log(msg); puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] #{msg}"; end

begin
  cn = WSApplication.current_network
  raise "ERROR: 'cn' (current network) is nil. Please ensure it's loaded." if cn.nil?

  log "Starting inspection of 'sw_conduit' objects..."

  conduits = cn.row_objects('sw_conduit')
  if conduits.nil?
    log 'No sw_conduit collection returned (nil).'
  elsif conduits.respond_to?(:empty?) && conduits.empty?
    log 'No sw_conduit objects found (collection empty).'
  else
    size_str = conduits.respond_to?(:size) ? conduits.size.to_s : 'unknown'
    log "Found #{size_str} sw_conduit object(s)."
    pipe = conduits.respond_to?(:first) ? conduits.first : conduits.to_a.first
    if pipe
      pipe_id = if pipe.respond_to?(:id) && pipe.id
                  "ID: #{pipe.id}"
                elsif pipe.respond_to?(:asset_id) && pipe.asset_id
                  "Asset ID: #{pipe.asset_id}"
                else
                  'Object at index 0'
                end
      log "Inspecting: #{pipe_id}"

      if pipe.respond_to?(:fields)
        begin
          fo = pipe.fields
          log "pipe.fields output: #{fo.inspect}"
        rescue StandardError => fe
          log "Error calling pipe.fields: #{fe.class} - #{fe.message}"
        end
      else
        log "Object does not respond to .fields"
      end

      begin
        all_methods = pipe.methods.sort
        log "Total methods: #{all_methods.length}"
        sample = all_methods.grep(/id|node|link|value|user|geom|shape|length|width|height|invert|flow|setting/)
        sample = all_methods.first(20) if sample.empty?
        log "Sample methods: #{sample.take(30).join(', ')}..."
      rescue StandardError => me
        log "Error listing methods: #{me.message}"
      end
    end
  end
rescue StandardError => e
  log "Aborted: #{e.message}"
ensure
  log 'fix_check_fields.rb finished.'
end
