# frozen_string_literal: true

# Purpose: Create scenario with percentage change in runoff surfaces upstream node
# Inputs: UI script; user percentage inputs for 12 runoff areas; node selection; subcatchment type choice
# Outputs: Creates timestamped scenario with modified runoff areas; transaction control
# Type: UI script (runs in ICM context)
# Hardening: Begin/rescue/ensure, nil checks, transaction control, user validation

begin
  text = 'Make sure to press ENTER after inputting every number, otherwise the value might not be committed and the script will fail.'
  WSApplication.message_box(text,'OK','!','')

  title = 'Percentage Change in Runoff for Absolute Area'
  dialog = [
    ['Runoff Area 1','NUMBER',0],
    ['Runoff Area 2','NUMBER',0],
    ['Runoff Area 3','NUMBER',0],
    ['Runoff Area 4','NUMBER',0],
    ['Runoff Area 5','NUMBER',0],
    ['Runoff Area 6','NUMBER',0],
    ['Runoff Area 7','NUMBER',0],
    ['Runoff Area 8','NUMBER',0],
    ['Runoff Area 9','NUMBER',0],
    ['Runoff Area 10','NUMBER',0],
    ['Runoff Area 11','NUMBER',0],
    ['Runoff Area 12','NUMBER',0],
    ['Subcatchment type','String','Foul',nil,'LIST',['Foul','Storm','Sanitary','combined','overland','other']],
  ]

  $user_input = WSApplication.prompt(title,dialog,false)
  raise 'Script aborted by user' if $user_input.nil?

  def update_subs(node)
    raise 'Node is nil' if node.nil?

    subs = node.navigate('subcatchments')
    return if subs.nil?

    subs.each do |subs|
      if subs.system_type.downcase == $user_input[12].downcase
        subs.selected = true
        subs.area_absolute_1 = subs.area_absolute_1 * (1 + $user_input[0]/100) if $user_input[0] != 0
        subs.area_absolute_2 = subs.area_absolute_2 * (1 + $user_input[1]/100) if $user_input[1] != 0
        subs.area_absolute_3 = subs.area_absolute_3 * (1 + $user_input[2]/100) if $user_input[2] != 0
        subs.area_absolute_4 = subs.area_absolute_4 * (1 + $user_input[3]/100) if $user_input[3] != 0
        subs.area_absolute_5 = subs.area_absolute_5 * (1 + $user_input[4]/100) if $user_input[4] != 0
        subs.area_absolute_6 = subs.area_absolute_6 * (1 + $user_input[5]/100) if $user_input[5] != 0
        subs.area_absolute_7 = subs.area_absolute_7 * (1 + $user_input[6]/100) if $user_input[6] != 0
        subs.area_absolute_8 = subs.area_absolute_8 * (1 + $user_input[7]/100) if $user_input[7] != 0
        subs.area_absolute_9 = subs.area_absolute_9 * (1 + $user_input[8]/100) if $user_input[8] != 0
        subs.area_absolute_10 = subs.area_absolute_10 * (1 + $user_input[9]/100) if $user_input[9] != 0
        subs.area_absolute_11 = subs.area_absolute_11 * (1 + $user_input[10]/100) if $user_input[10] != 0
        subs.area_absolute_12 = subs.area_absolute_12 * (1 + $user_input[11]/100) if $user_input[11] != 0
        subs.area_absolute_1_flag = "SCRP"
        subs.area_absolute_2_flag = "SCRP"
        subs.area_absolute_3_flag = "SCRP"
        subs.write
      end
    end
  end

  def scenario
    time = Time.new.strftime('%Y%m%d_%k%M%S').to_s
    $net.add_scenario(time,nil,time)
    $net.current_scenario = time
    time
  end

  $net = WSApplication.current_network
  raise 'Network is not open' if $net.nil?

  $roc = $net.row_object_collection_selection('_nodes')
  raise 'No nodes selected' if $roc.nil? || $roc.empty?

  $unprocessedLinks = Array.new

  scenario_name = scenario

  $net.transaction_begin
  $roc.each do |ro|
    update_subs(ro)
    ro.us_links.each do |l|
      if !l._seen
        $unprocessedLinks << l
        l._seen = true
      end
    end

    while $unprocessedLinks.size > 0
      working = $unprocessedLinks.shift
      working.selected = true
      workingUSNode = working.us_node

      if !workingUSNode.nil? && !workingUSNode._seen
        workingUSNode.selected = true
        update_subs(workingUSNode)
        workingUSNode.us_links.each do |l|
          if !l._seen
            $unprocessedLinks << l
            l.selected = true
            l._seen = true
          end
        end
      end
    end
  end

  $net.transaction_commit

  puts "Scenario #{scenario_name} created with runoff percentage changes."

rescue => e
  puts "Error creating runoff scenario: #{e.message}"
  begin
    $net&.transaction_rollback
  rescue
    # Ignore rollback errors
  end
  WSApplication.message_box("Error: #{e.message}", 'OK', '!', false)
ensure
  # Cleanup _seen markers
  begin
    $net&.row_object_collection('_links')&.each { |l| l._seen = false }
  rescue
    # Ignore cleanup errors
  end
end
