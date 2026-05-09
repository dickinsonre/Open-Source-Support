# frozen_string_literal: true
# ---------------------------------------------------------------------------
# fix_hw_simulation_parameters.rb
#
# Purpose : Diagnostic - probes the current_network for ways to access
#           parameter / defaults tables (hw_sim_parameters, hw_*_defaults,
#           hw_wq_params).  Reports which row_object/row_objects calling
#           conventions work in this version of ICM.
# Inputs  : Active current_network.
# Outputs : Console diagnostic listing.
# Type    : UI script.
# Hardening:
#   * frozen_string_literal pragma
#   * Validates current_network not nil
#   * Per-test rescue
#   * begin/rescue/ensure with timestamped logging
# ---------------------------------------------------------------------------

def log(msg); puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] #{msg}"; end

begin
  cn = WSApplication.current_network
  raise 'No current network is open.' if cn.nil?

  log "=== Debugging Parameter Table Access Methods ==="
  log "Network object class: #{cn.class}"

  begin
    log "--- Network object methods containing 'sim' or 'param' ---"
    cn.methods.grep(/sim|param/i).sort.each { |m| puts "  cn.#{m}" }
  rescue StandardError => me
    log "method probe failed: #{me.message}"
  end

  if cn.respond_to?(:current_sim)
    log '--- current_sim is available ---'
    current_sim = cn.current_sim
    if current_sim
      log "current_sim class: #{current_sim.class}"
      current_sim.methods.grep(/param|row/i).sort.each { |m| puts "  current_sim.#{m}" }
      if current_sim.respond_to?(:hw_sim_parameters)
        begin
          obj = current_sim.hw_sim_parameters
          log "current_sim.hw_sim_parameters returned #{obj.class}"
        rescue StandardError => se
          log "current_sim.hw_sim_parameters failed: #{se.message}"
        end
      end
    else
      log 'current_sim is nil'
    end
  else
    log '--- current_sim is NOT available ---'
  end

  if cn.respond_to?(:options)
    options = cn.options
    if options
      log "options class: #{options.class}"
      options.methods.grep(/default/i).sort.each { |m| puts "  options.#{m}" }
    end
  end

  log '--- Testing row_object methods ---'
  test_table = 'hw_sim_parameters'
  [[:one, [test_table]], [:empty, [test_table, '']], [:nil, [test_table, nil]]].each do |label, args|
    begin
      obj = cn.row_object(*args)
      log "SUCCESS: cn.row_object(#{args.inspect}) (#{label}) -> #{obj.class}"
    rescue StandardError => re
      log "FAILED: cn.row_object(#{args.inspect}) (#{label}) -> #{re.message}"
    end
  end

  begin
    objects = cn.row_objects(test_table)
    if objects
      count = 0
      objects.each { count += 1 }
      log "cn.row_objects('#{test_table}') -> #{objects.class} count=#{count}"
    end
  rescue StandardError => re
    log "row_objects failed: #{re.message}"
  end

  %w[hw_sim_parameters hw_manhole_defaults hw_conduit_defaults hw_subcatchment_defaults hw_wq_params].each do |t|
    log "Probe #{t}:"
    log "  cn.#{t} exists" if cn.respond_to?(t.to_sym)
    if cn.respond_to?(:current_sim) && cn.current_sim && cn.current_sim.respond_to?(t.to_sym)
      log "  cn.current_sim.#{t} exists"
    end
    if cn.respond_to?(:options) && cn.options && cn.options.respond_to?(t.to_sym)
      log "  cn.options.#{t} exists"
    end
  end
rescue StandardError => e
  log "Aborted: #{e.message}"
ensure
  log 'fix_hw_simulation_parameters.rb finished.'
end
