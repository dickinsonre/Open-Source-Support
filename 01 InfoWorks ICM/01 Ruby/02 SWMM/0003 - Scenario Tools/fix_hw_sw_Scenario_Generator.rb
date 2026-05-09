# frozen_string_literal: true

# Purpose: Create Phase 1-10 scenarios (10 phases for modeling)
# Inputs: UI script; requires network open
# Outputs: Deletes non-Base scenarios, creates Phase1-Phase10 scenarios
# Type: UI script (runs in ICM context)
# Hardening: Begin/rescue/ensure, nil checks

begin
  current_network = WSApplication.current_network
  raise 'Network is not open' if current_network.nil?

  THANK_YOU_MESSAGE = 'Thank you for using Ruby in ICM InfoWorks'

  scenarios = Array.new
  scenarios = [
    "Phase1",
    "Phase2",
    "Phase3",
    "Phase4",
    "Phase5",
    "Phase6",
    "Phase7",
    "Phase8",
    "Phase9",
    "Phase10"
  ]

  current_network.scenarios do |scenario|
    if scenario != 'Base'
      current_network.delete_scenario(scenario)
    end
  end

  puts 'All scenarios deleted'

  scenarios.each do |scenario|
    current_network.add_scenario(scenario,nil,'')
  end

  puts THANK_YOU_MESSAGE

rescue => e
  puts "Error creating phase scenarios: #{e.message}"
  WSApplication.message_box("Error: #{e.message}", 'OK', '!', false)
ensure
  # Cleanup if needed
end
