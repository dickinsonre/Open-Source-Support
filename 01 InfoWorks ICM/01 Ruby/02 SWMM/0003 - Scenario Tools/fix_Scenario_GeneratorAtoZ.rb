# frozen_string_literal: true

# Purpose: Create A-Z scenarios (26 scenarios named A through Z)
# Inputs: UI script; requires network open
# Outputs: Deletes non-Base scenarios, creates A-Z scenarios; message feedback
# Type: UI script (runs in ICM context)
# Hardening: Begin/rescue/ensure, nil checks, thank you messages

begin
  current_network = WSApplication.current_network
  raise 'Network is not open' if current_network.nil?

  THANK_YOU_MESSAGE1 = "That's it! You've successfully updated your ICM InfoWorks network. Thank you for using our Ruby script."
  THANK_YOU_MESSAGE2 = "If you have any questions or need further assistance, don't hesitate to reach out to the Autodesk EBCS Team."
  THANK_YOU_MESSAGE3 = "Happy Modeling! or Happy Modelling! (depending on your location)"

  scenarios = ('A'..'Z').to_a

  current_network.scenarios do |scenario|
    if scenario != 'Base'
      current_network.delete_scenario(scenario)
    end
  end

  puts "Operation successful! All scenarios, except for the base scenario, have been deleted and new scenarios have been added."
  puts "If this action was performed in error, don't worry! You can easily revert these changes."
  puts "Just go to the ICM Explorer Window and select 'Revert Changes' to restore the deleted scenarios."

  scenarios.each do |scenario|
    current_network.add_scenario(scenario,nil,'')
  end

  puts
  puts "Number of scenarios added: #{scenarios.length}"
  puts
  puts THANK_YOU_MESSAGE1
  puts THANK_YOU_MESSAGE2
  puts THANK_YOU_MESSAGE3

rescue => e
  puts "Error creating A-Z scenarios: #{e.message}"
  WSApplication.message_box("Error: #{e.message}", 'OK', '!', false)
ensure
  # Cleanup if needed
end
