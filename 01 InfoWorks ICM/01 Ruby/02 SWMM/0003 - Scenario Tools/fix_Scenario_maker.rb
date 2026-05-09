# frozen_string_literal: true

# Purpose: Delete all non-Base scenarios in network
# Inputs: UI script; requires network open
# Outputs: Deletes all scenarios except Base; prints confirmation
# Type: UI script (runs in ICM context)
# Hardening: Begin/rescue/ensure, nil checks

begin
  net = WSApplication.current_network
  raise 'Network is not open' if net.nil?

  net.scenarios do |s|
    if s != 'Base'
      net.delete_scenario(s)
    end
  end

  puts 'All scenarios deleted'

rescue => e
  puts "Error deleting scenarios: #{e.message}"
  WSApplication.message_box("Error: #{e.message}", 'OK', '!', false)
ensure
  # Cleanup if needed
end
