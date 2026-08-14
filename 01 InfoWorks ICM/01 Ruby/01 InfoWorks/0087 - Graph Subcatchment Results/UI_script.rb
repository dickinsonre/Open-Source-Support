# Universal Results Grapher: auto-detects object type and network type (ICM / SWMM).
# Select any mix of subcatchments, nodes, and links, then run.
# Each selected object gets one graph with all non-zero result fields overlaid.
# When 2+ objects of the same type are selected, a comparison graph is added.
require 'date'
catch(:stop) do
 
net = WSApplication.current_network
selected = []
net.each_selected { |sel| selected << sel }
 
if selected.empty?
  WSApplication.message_box('Please select one or more objects (subcatchments, nodes, or links).', 'OK', 'Information', false)
  throw :stop
end
 
timesteps = net.list_timesteps
if timesteps.nil? || timesteps.count.zero?
  WSApplication.message_box('No timesteps found. Run a simulation and open results.', 'OK', 'Information', false)
  throw :stop
end
 
ts_count = timesteps.count
 
# ---------- helpers ----------
 
def fetch_series(ro, field, ts_count)
  vals = []
  begin
    res = ro.results(field)
    res.each { |v| vals << v.to_f } unless res.nil?
  rescue StandardError
    vals = []
  end
  if vals.size == 1
    vals = Array.new(ts_count, vals[0])
  end
  return nil if vals.size != ts_count
  vals
end
 
def zero?(vals)
  vals.each { |v| return false if v.abs > 1.0e-12 }
  true
end
 
def show_graph(opts, timesteps, ts_count)
  begin
    WSApplication.graph(opts)
  rescue StandardError
    step_array = (0...ts_count).to_a
    interval_label = 'Timestep'
    begin
      if ts_count > 1
        t0 = timesteps[0].to_f
        t1 = timesteps[1].to_f
        step_seconds = (t1 - t0).abs
        if step_seconds > 0
          if (step_seconds % 3600).abs < 1.0e-9
            interval_label = "Timestep (#{(step_seconds / 3600).round} hr)"
          elsif (step_seconds % 60).abs < 1.0e-9
            interval_label = "Timestep (#{(step_seconds / 60).round} min)"
          else
            interval_label = "Timestep (#{step_seconds.round(1)} s)"
          end
        end
      end
    rescue StandardError
      nil
    end
    opts['Traces'].each { |tr| tr['XArray'] = step_array }
    opts['IsTime'] = false
    opts['XAxisLabel'] = interval_label
    WSApplication.graph(opts)
  end
end
 
# ---------- table-name lookup for row_object ----------
 
# Map category symbols to ICM internal table names (try in order)
TABLE_NAMES = {
  :subcatchment => ['_subcatchments', 'hw_subcatchment'],
  :node         => ['_nodes', 'hw_node', 'hw_manhole', 'hw_storage', 'hw_outfall', 'hw_break',
                     '_swmm_nodes', 'swmm_junction', 'swmm_outfall', 'swmm_storage'],
  :link         => ['_links', 'hw_conduit', 'hw_pump', 'hw_orifice', 'hw_weir', 'hw_sluice',
                     '_swmm_links', 'swmm_conduit', 'swmm_pump', 'swmm_orifice', 'swmm_weir']
}
 
def find_row_object(net, obj_id, category)
  TABLE_NAMES[category].each do |tbl|
    begin
      ro = net.row_object(tbl, obj_id)
      return ro unless ro.nil?
    rescue StandardError
      next
    end
  end
  nil
end
 
# ---------- result field definitions per object category ----------
# Each entry: [field_name, display_label, [r, g, b]]
 
SUBCATCH_FIELDS = [
  # ICM subcatchment results
  ['qcatch',       'Total outflow',          [0, 0, 0]],
  ['qbase',        'Baseflow',               [100, 100, 100]],
  ['qtrade',       'Trade flow',             [180, 100, 0]],
  ['qfoul',        'Foul flow',              [160, 0, 160]],
  ['qrdii',        'RDII',                   [0, 160, 160]],
  ['qground',      'Ground store inflow',    [0, 120, 200]],
  ['qsoil',        'Soil store inflow',      [220, 100, 0]],
  ['qsurf01',      'Surface runoff 1',       [200, 0, 0]],
  ['qsurf02',      'Surface runoff 2',       [220, 60, 60]],
  ['qsurf03',      'Surface runoff 3',       [240, 100, 100]],
  ['qsurf04',      'Surface runoff 4',       [255, 140, 140]],
  ['qsurf05',      'Surface runoff 5',       [0, 120, 0]],
  ['qsurf06',      'Surface runoff 6',       [60, 160, 60]],
  ['qsurf07',      'Surface runoff 7',       [100, 180, 100]],
  ['qsurf08',      'Surface runoff 8',       [140, 200, 140]],
  ['qsurf09',      'Surface runoff 9',       [0, 0, 180]],
  ['qsurf10',      'Surface runoff 10',      [60, 60, 200]],
  ['qsurf11',      'Surface runoff 11',      [100, 100, 220]],
  ['qsurf12',      'Surface runoff 12',      [140, 140, 240]],
  ['q_lid_in',     'LID inflow',             [180, 0, 180]],
  ['q_lid_out',    'LID outflow',            [200, 80, 200]],
  ['q_lid_drain',  'LID drain',              [220, 120, 220]],
  ['q_exceedance', 'Exceedance flow',        [200, 200, 0]],
  # SWMM subcatchment results
  ['runoff',       'SWMM Runoff',            [200, 0, 0]],
  ['infiltration', 'SWMM Infiltration',      [0, 120, 0]],
  ['evaporation',  'SWMM Evaporation',       [0, 0, 200]],
  ['rainfall',     'SWMM Rainfall',          [0, 80, 180]],
  ['snow_depth',   'SWMM Snow depth',        [100, 100, 220]],
  ['gwflow',       'SWMM GW flow',           [0, 160, 160]],
  ['gw_elev',      'SWMM GW elevation',      [120, 80, 40]],
  ['sw_runon',     'SWMM Runon',             [180, 100, 0]],
  ['losses',       'SWMM Losses',            [160, 0, 160]]
]
 
NODE_FIELDS = [
  # ICM node results
  ['depnod',       'Depth',                  [0, 0, 200]],
  ['floodnod',     'Flood depth',            [200, 0, 0]],
  ['volnod',       'Volume',                 [0, 160, 0]],
  ['totnod',       'Total inflow',           [0, 0, 0]],
  ['ds_inflow',    'DS inflow',              [120, 80, 40]],
  ['flood_vol',    'Flood volume',           [200, 0, 0]],
  ['qnode',        'Flow at node',           [0, 120, 200]],
  ['surcharge',    'Surcharge depth',        [220, 100, 0]],
  ['ponded_vol',   'Ponded volume',          [0, 160, 160]],
  # SWMM node results
  ['total_inflow', 'SWMM Total inflow',      [0, 0, 0]],
  ['total_outflow','SWMM Total outflow',     [100, 100, 100]],
  ['flooding',     'SWMM Flooding',          [200, 0, 0]],
  ['depth',        'SWMM Depth',             [0, 0, 200]],
  ['head',         'SWMM Head',              [0, 120, 200]],
  ['volume',       'SWMM Volume',            [0, 160, 0]],
  ['lateral_inflow','SWMM Lateral inflow',   [180, 100, 0]],
  ['lat_inflow',   'SWMM Lat inflow',        [180, 100, 0]]
]
 
LINK_FIELDS = [
  # ICM link results
  ['us_flow',      'US flow',                [0, 0, 200]],
  ['ds_flow',      'DS flow',                [0, 120, 200]],
  ['us_depth',     'US depth',               [200, 0, 0]],
  ['ds_depth',     'DS depth',               [220, 60, 60]],
  ['us_vel',       'US velocity',            [0, 160, 0]],
  ['ds_vel',       'DS velocity',            [60, 160, 60]],
  ['us_froude',    'US Froude',              [180, 100, 0]],
  ['ds_froude',    'DS Froude',              [220, 140, 0]],
  ['surcharge_depth','Surcharge depth',      [160, 0, 160]],
  ['flow',         'Flow',                   [0, 0, 0]],
  ['capacity',     'Capacity',               [100, 100, 100]],
  # SWMM link results
  ['flow_rate',    'SWMM Flow rate',         [0, 0, 200]],
  ['flow_depth',   'SWMM Flow depth',        [200, 0, 0]],
  ['flow_velocity','SWMM Velocity',          [0, 160, 0]],
  ['froude',       'SWMM Froude',            [180, 100, 0]],
  ['flow_area',    'SWMM Flow area',         [0, 120, 200]],
  ['setting',      'SWMM Setting',           [160, 0, 160]],
  ['pump_flow',    'SWMM Pump flow',         [0, 160, 160]]
]
 
# ---------- classify selected objects ----------
 
classified = { :subcatchment => [], :node => [], :link => [] }
 
selected.each do |sel_obj|
  obj_id   = sel_obj.id
  obj_type = nil
 
  begin
    obj_type = sel_obj.table.downcase
  rescue StandardError
    obj_type = ''
  end
 
  if obj_type.include?('subcatchment') || obj_type.include?('subcatch')
    classified[:subcatchment] << obj_id
  elsif obj_type.include?('conduit') || obj_type.include?('pump') || obj_type.include?('orifice') ||
        obj_type.include?('weir') || obj_type.include?('sluice') || obj_type.include?('link')
    classified[:link] << obj_id
  elsif obj_type.include?('node') || obj_type.include?('manhole') || obj_type.include?('storage') ||
        obj_type.include?('outfall') || obj_type.include?('junction') || obj_type.include?('break')
    classified[:node] << obj_id
  else
    # Try each category by attempting to find the row object
    ro = find_row_object(net, obj_id, :subcatchment)
    if ro
      classified[:subcatchment] << obj_id
      next
    end
    ro = find_row_object(net, obj_id, :node)
    if ro
      classified[:node] << obj_id
      next
    end
    ro = find_row_object(net, obj_id, :link)
    if ro
      classified[:link] << obj_id
      next
    end
  end
end
 
total_found = classified.values.map(&:size).inject(0, :+)
if total_found.zero?
  WSApplication.message_box('No recognised subcatchments, nodes, or links in selection.', 'OK', 'Information', false)
  throw :stop
end
 
# ---------- colour helper ----------
 
def make_colour(rgb)
  WSApplication.colour(rgb[0], rgb[1], rgb[2])
end
 
# ---------- graph each category ----------
 
FIELD_MAP = {
  :subcatchment => SUBCATCH_FIELDS,
  :node         => NODE_FIELDS,
  :link         => LINK_FIELDS
}
 
CATEGORY_LABELS = {
  :subcatchment => 'Subcatchment',
  :node         => 'Node',
  :link         => 'Link'
}
 
# Primary field for cross-object comparison graph
PRIMARY_FIELD = {
  :subcatchment => ['qcatch', 'runoff'],
  :node         => ['depnod', 'depth', 'total_inflow'],
  :link         => ['us_flow', 'ds_flow', 'flow', 'flow_rate']
}
 
palette = [
  [0,0,0],[200,0,0],[0,120,0],[0,0,200],[200,120,0],
  [160,0,160],[0,160,160],[120,80,40],[200,0,100],[0,200,100],
  [100,100,220],[220,60,60],[60,160,60],[60,60,200],[180,180,0],
  [0,120,200],[200,80,200],[140,200,140],[100,0,0],[0,100,100]
]
 
[:subcatchment, :node, :link].each do |cat|
  ids = classified[cat]
  next if ids.empty?
 
  field_defs  = FIELD_MAP[cat]
  cat_label   = CATEGORY_LABELS[cat]
  skipped     = []
  compare_data = []  # for comparison graph
  ci = 0
 
  ids.each do |obj_id|
    ro = find_row_object(net, obj_id, cat)
    if ro.nil?
      skipped << obj_id
      next
    end
 
    # Try every field, keep non-zero ones
    traces = []
    field_defs.each do |fname, flabel, frgb|
      vals = fetch_series(ro, fname, ts_count)
      next if vals.nil?
      next if zero?(vals)
      traces << { 'Title' => "#{flabel} (#{fname})", 'TraceColour' => make_colour(frgb),
                  'LineType' => 'Solid', 'Marker' => 'None',
                  'XArray' => timesteps, 'YArray' => vals }
    end
 
    if traces.empty?
      skipped << obj_id
      next
    end
 
    opts = { 'YAxisLabel' => 'Value', 'XAxisLabel' => 'Time', 'IsTime' => true, 'Traces' => traces }
    opts['WindowTitle'] = opts['GraphTitle'] = "#{cat_label} results - #{obj_id} (#{traces.size} fields)"
    show_graph(opts, timesteps, ts_count)
 
    # Store primary field for comparison
    PRIMARY_FIELD[cat].each do |pf|
      vals = fetch_series(ro, pf, ts_count)
      if vals && !zero?(vals)
        c = palette[ci % palette.size]
        compare_data << { 'id' => obj_id, 'field' => pf, 'vals' => vals, 'colour' => c }
        ci += 1
        break
      end
    end
  end
 
  # Comparison graph when 2+ objects in same category
  if compare_data.size > 1
    cmp_traces = []
    compare_data.each do |d|
      cmp_traces << { 'Title' => "#{d['id']} (#{d['field']})",
                      'TraceColour' => make_colour(d['colour']),
                      'LineType' => 'Solid', 'Marker' => 'None',
                      'XArray' => timesteps, 'YArray' => d['vals'] }
    end
    opts = { 'YAxisLabel' => 'Value', 'XAxisLabel' => 'Time', 'IsTime' => true, 'Traces' => cmp_traces }
    opts['WindowTitle'] = opts['GraphTitle'] = "#{cat_label} comparison - #{cmp_traces.size} objects"
    show_graph(opts, timesteps, ts_count)
  end
 
  unless skipped.empty?
    WSApplication.message_box("Skipped #{cat_label}s (not found or no results):\n#{skipped.join(', ')}", 'OK', 'Information', false)
  end
end
 
end
 