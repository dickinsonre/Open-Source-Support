# frozen_string_literal: true
# ---------------------------------------------------------------------------
# fix_Scenario_GIM.rb
#
# Purpose : Generates a parametric sweep of scenarios on a ground-infiltration
#           parameter (percolation_coefficient) for an InfoWorks ICM network.
# Inputs  : Active InfoWorks current_network with hw_ground_infiltration rows.
#           User selects USA/SI units via WSApplication.prompt.
# Outputs : New scenario branches named "<param>_factor_<pct>" with the
#           percolation_coefficient scaled by (1 + factor).
# Type    : UI script (uses WSApplication.current_network and prompt).
# Hardening:
#   * frozen_string_literal pragma
#   * Validates current_network not nil
#   * Validates prompt result not cancelled
#   * Wraps main logic in begin/rescue/ensure
#   * transaction_begin paired with rollback on error
#   * Nil-safe access to row attributes
#   * Timestamped progress logging
# Source  : Adapted from https://github.com/ngerdts7/ICM_Tools123
# ---------------------------------------------------------------------------

def log(msg)
  puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] #{msg}"
end

begin
  cn = WSApplication.current_network
  raise 'No current network is open. Open a network and try again.' if cn.nil?

  val = WSApplication.prompt(
    'Scenario Sensitivity Parameter Selection',
    [
      ['USA Units', 'Boolean', false],
      ['SI  Units', 'Boolean', true]
    ],
    false
  )
  raise 'Prompt was cancelled by the user.' if val.nil?

  THANK_YOU_MESSAGE1 = "That's it! You've successfully added scenarios your ICM InfoWorks network. Thank you for using our Ruby script."
  THANK_YOU_MESSAGE2 = "If you have any questions or need further assistance, don't hesitate to reach out to the Autodesk EBCS Team."
  THANK_YOU_MESSAGE3 = 'Happy Modeling! or Happy Modelling! (depending on your location)'

  factors    = [-0.25, -0.10, 0.10, 0.25]
  parameters = ['percolation_coefficient']

  scenarios = parameters.product(factors).map do |parameter, factor|
    "#{parameter}_factor_#{(factor * 100).to_i}"
  end

  log 'Deleting all scenarios except Base...'
  cn.scenarios do |scenario|
    cn.delete_scenario(scenario) if scenario != 'Base'
  end
  log 'Existing non-Base scenarios deleted (if any).'

  in_transaction = false
  scenarios.zip(factors).each do |scenario, factor|
    begin
      cn.add_scenario(scenario, nil, '')
      cn.current_scenario = scenario
      cn.transaction_begin
      in_transaction = true

      log "Scenario #{scenario}: applying factor #{factor}"
      cn.row_objects('hw_ground_infiltration').each do |ro|
        next if ro.nil?
        next if ro.percolation_coefficient.nil?
        ro.percolation_coefficient = ro.percolation_coefficient * (1 + factor)
        ro.write
      end

      cn.transaction_commit
      in_transaction = false
    rescue StandardError => scen_err
      log "Error in scenario #{scenario}: #{scen_err.message}"
      if in_transaction
        begin
          cn.transaction_rollback
        rescue StandardError
          # ignore secondary failure
        end
        in_transaction = false
      end
      raise
    end
  end

  log "Number of scenarios added: #{scenarios.length}"
  puts THANK_YOU_MESSAGE1
  puts THANK_YOU_MESSAGE2
  puts THANK_YOU_MESSAGE3
rescue StandardError => e
  log "Aborted: #{e.message}"
  log e.backtrace.first(5).join("\n") if e.backtrace
ensure
  log 'fix_Scenario_GIM.rb finished.'
end
