# frozen_string_literal: true

# Purpose: Create specific named scenarios (Future II variants)
# Inputs: UI script; requires network open
# Outputs: Deletes non-Base scenarios, creates specific named scenarios
# Type: UI script (runs in ICM context)
# Hardening: Begin/rescue/ensure, nil checks, hardcoded scenario list

begin
  current_network = WSApplication.current_network
  raise 'Network is not open' if current_network.nil?

  THANK_YOU_MESSAGE = 'Thank you for using Ruby in ICM InfoWorks'

  scenarios = Array.new
  scenarios = [
    "FUTURE_II",
    "FUTURE_II_2023",
    "FUT_II_I25",
    "FU_II_ALT1_I25_LS",
    "U_II_ALT1_I25_LS"
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
  puts "Error creating specific scenarios: #{e.message}"
  WSApplication.message_box("Error: #{e.message}", 'OK', '!', false)
ensure
  # Cleanup if needed
end
