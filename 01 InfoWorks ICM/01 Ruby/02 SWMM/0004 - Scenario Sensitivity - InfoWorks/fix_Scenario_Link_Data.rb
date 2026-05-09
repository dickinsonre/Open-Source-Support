# frozen_string_literal: true
# ---------------------------------------------------------------------------
# fix_Scenario_Link_Data.rb
#
# Purpose : Generates parametric scenarios that scale conduit bottom roughness
#           (Manning's n) on hw_conduit rows.  Used for sensitivity sweeps.
# Inputs  : Active InfoWorks current_network with hw_conduit rows.
#           User picks unit type and width option via WSApplication.prompt.
# Outputs : New scenario branches "<param>_factor_<pct>" with bottom_roughness_N
#           scaled by (1 + factor).  Reports total network roughness per scenario.
# Type    : UI script (uses WSApplication.current_network and prompt).
# Hardening:
#   * frozen_string_literal pragma
#   * Validates current_network not nil and prompt not cancelled
#   * begin/rescue/ensure around main logic
#   * transaction_begin paired with rollback on error
#   * Nil-safe attribute access (next if ro.nil?)
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
      ['SI  Units', 'Boolean', true],
      ['Width = 1.7 * Max(Height, Width)', 'Boolean', false],
      ['Width = K * SQRT(Area)', 'Boolean', false],
      ['Width = K * Perimeter', 'Boolean', false],
      ['Width = Area / Flow Length', 'Boolean', false],
      ['K value 0.2 to 5 default of 1', 'String'],
      ['Choose the Unit type and Width Option', 'String']
    ],
    false
  )
  raise 'Prompt was cancelled by the user.' if val.nil?

  THANK_YOU_MESSAGE1 = "That's it! You've successfully added scenarios your ICM InfoWorks network. Thank you for using our Ruby script."
  THANK_YOU_MESSAGE2 = "If you have any questions or need further assistance, don't hesitate to reach out to the Autodesk EBCS Team."
  THANK_YOU_MESSAGE3 = 'Happy Modeling! or Happy Modelling! (depending on your location)'

  factors    = [-0.25, -0.10, 0.10, 0.25]
  parameters = ['bottom_roughness_N']

  scenarios = parameters.product(factors).map do |parameter, factor|
    "#{parameter}_factor_#{(factor * 100).to_i}"
  end

  log 'Deleting all scenarios except Base...'
  cn.scenarios do |scenario|
    cn.delete_scenario(scenario) if scenario != 'Base'
  end

  in_transaction = false
  scenarios.zip(factors).each do |scenario, factor|
    begin
      cn.add_scenario(scenario, nil, '')
      cn.current_scenario = scenario
      cn.transaction_begin
      in_transaction = true
      br_n = []

      log "Scenario #{scenario}: applying factor #{factor}"
      cn.row_objects('hw_conduit').each do |ro|
        next if ro.nil?
        next if ro.bottom_roughness_N.nil?
        ro.bottom_roughness_N = ro.bottom_roughness_N * (1 + factor)
        br_n << ro.bottom_roughness_N
        ro.write
      end

      total = br_n.compact.sum.round(5)
      log "Scenario #{cn.current_scenario}: total bottom_roughness_N = #{total} across #{br_n.count} links"

      cn.transaction_commit
      in_transaction = false
    rescue StandardError => scen_err
      log "Error in scenario #{scenario}: #{scen_err.message}"
      if in_transaction
        begin
          cn.transaction_rollback
        rescue StandardError
          # ignore
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
  log 'fix_Scenario_Link_Data.rb finished.'
end
