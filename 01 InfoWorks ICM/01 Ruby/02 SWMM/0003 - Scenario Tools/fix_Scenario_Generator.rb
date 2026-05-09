# frozen_string_literal: true

# Purpose: Generate scenarios by varying 8 parameters with configurable ranges
# Inputs: UI script; requires network open; hardcoded parameter definitions
# Outputs: Creates scenarios with varied parameters; validates each scenario
# Type: UI script (runs in ICM context)
# Hardening: Begin/rescue/ensure, nil checks, transaction control per scenario

begin
  current_network = WSApplication.current_network
  raise 'Network is not open' if current_network.nil?

  # Define which parameters will be varied by the script.
  # Key   = name of ICM variable to be modified
  # name  = abbreviation of parameter to be used in scenario name
  # table = name of table to be edited that contains the parameter
  # id    = model ID in specified table where parameter changes are made
  # Range = [min, max, # of steps]

  param = Hash.new
  param['p_area_1'] =               {'name'=>'p1', 'table'=>'hw_land_use',            'id'=>'12430', 'Range'=>[0.3,1,2]}
  param['p_area_2'] =               {'name'=>'p2', 'table'=>'hw_land_use',            'id'=>'12430', 'Range'=>[10,20,2]}
  param['runoff_routing_value'] =   {'name'=>'rv', 'table'=>'hw_runoff_surface',      'id'=>'2',     'Range'=>[10,30,2]}
  param['percolation_coefficient'] ={'name'=>'pc', 'table'=>'hw_ground_infiltration', 'id'=>'12430', 'Range'=>[2,10,3]}
  param['percolation_threshold'] =  {'name'=>'pt', 'table'=>'hw_ground_infiltration', 'id'=>'12430', 'Range'=>[40,80,3]}
  param['percolation_percentage'] = {'name'=>'pp', 'table'=>'hw_ground_infiltration', 'id'=>'12430', 'Range'=>[15,25,2]}
  param['baseflow_coefficient'] =   {'name'=>'bc', 'table'=>'hw_ground_infiltration', 'id'=>'12430', 'Range'=>[30,50,2]}
  param['infiltration_coefficient']={'name'=>'ic', 'table'=>'hw_ground_infiltration', 'id'=>'12430', 'Range'=>[10,20,2]}
  var = param.keys

  # Method to convert range array into array of values to be used
  def list_values(range_array)
    dx = (range_array[1]-range_array[0])/(range_array[2]-1.00)
    Array.new(range_array[2]) {|i| i*dx+range_array[0]}
  end

  # Method to generate a new scenario and apply parameter changes based on input set
  def create_scenario(param,var,vars,net)
    scenario = ''
    for i in 0..var.length-1
      # assemble unique scenario name based on parameter composition
      scenario << param[var[i]]['name'] + "=" + vars[i].to_s + "_"
    end

    net.add_scenario(scenario,nil,'')
    net.current_scenario=scenario
    net.clear_selection
    net.transaction_begin
    begin
      for i in 0..var.length-1
        # Apply parameter changes in scenario as defined by vars array
        puts param[var[i]]['table']
        puts param[var[i]]['id']
        row_obj = net.row_object(param[var[i]]['table'],param[var[i]]['id'])
        raise "Row object not found for #{var[i]}" if row_obj.nil?

        row_obj[var[i]] = vars[i]
        row_obj.write
      end
      net.transaction_commit
      v = net.validate(scenario)
      scenario
    rescue => e
      net.transaction_rollback
      raise e
    end
  end

  # Generate scenarios for every possible parameter combination
  scenarios = []
  variations = var.map { |v| list_values(param[v]['Range']) }
  variations.first.product(*variations[1..-1]) do |vars|
    scenario = create_scenario(param, var, vars, current_network)
    puts "Configured scenario #{scenario} with #{vars.length} variables"
    scenarios << scenario
  end

  puts "\nTotal scenarios created: #{scenarios.length}"

rescue => e
  puts "Error generating scenarios: #{e.message}"
  begin
    current_network&.transaction_rollback
  rescue
    # Ignore rollback errors
  end
  WSApplication.message_box("Error: #{e.message}", 'OK', '!', false)
ensure
  # Cleanup if needed
end
