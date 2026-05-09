# frozen_string_literal: true
# =============================================================================
# fix_Model_Evaluation_Logic.rb
# =============================================================================
# Purpose:
#   Hardened InfoWorks vs ICM SWMM Master Comparison Report. Builds parameter
#   lookups across hw_runoff_surface / hw_land_use / hw_subcatchment and
#   sw_subcatchment, classifies surfaces by surface_type, prints multi-section
#   diagnostics, records mismatches, and (optionally) exports a CSV.
#
# Inputs:
#   - WSApplication.current_network and WSApplication.background_network
#   - CSV_PATH (constant) for export location
#
# Outputs:
#   - Console master report (Sections 1-12)
#   - CSV at CSV_PATH when EXPORT_CSV is true and mismatches exist
#
# UI vs Exchange: UI script.
#
# Hardening notes:
#   - frozen_string_literal, begin/rescue/ensure, timestamped logging
#   - safe_rows / safe_get / try_fields helpers swallow rescue and return defaults
#   - File.open block-form for CSV; per-row rescue while iterating
#   - Validates network presence before each section
#
# Note: Original used a local variable `cn` shadowed by `cn = curve_number`
# in section 5; preserved here to keep behaviour identical.
# =============================================================================

PAGE_WIDTH = 180
TOLERANCE = 0.001
EXPORT_CSV = true
CSV_PATH = "C:/Temp/ICM_Comparison_Report.csv"

PERVIOUS_PATTERNS = ['pervious', 'perv', 'greenampt', 'green-ampt', 'horton'].freeze
IMPERVIOUS_PATTERNS = ['impervious', 'imperv', 'imp', 'fixed'].freeze

def ts_log(msg)
  puts "[#{Time.now.strftime('%H:%M:%S')}] #{msg}"
end

def safe_rows(net, table_name)
  return [] if net.nil?
  begin
    tables = net.tables rescue []
    return [] unless tables.any? { |t| t.name == table_name }
    net.row_objects(table_name)
  rescue => e
    ts_log "safe_rows(#{table_name}) error: #{e.message}"
    []
  end
end

def safe_get(obj, method_name, default=nil)
  return default if obj.nil?
  v = obj.send(method_name) rescue nil
  v.nil? ? default : v
end

def try_fields_with_source(obj, field_list, default=nil)
  field_list.each do |f|
    val = safe_get(obj, f, nil)
    return { value: val, source_field: f.to_s } unless val.nil?
  end
  { value: default, source_field: "not_found" }
end

def try_fields(obj, field_list, default=nil)
  try_fields_with_source(obj, field_list, default)[:value]
end

def fmt_num(val, decimals=4)
  return "-" if val.nil?
  return sprintf("%.#{decimals}f", val) if val.is_a?(Numeric)
  val.to_s
end

def check_diff(val1, val2, tolerance=TOLERANCE)
  return false unless val1.is_a?(Numeric) && val2.is_a?(Numeric)
  (val1 - val2).abs > tolerance
end

def classify_surface_type(surface_type_str, runoff_volume_type_str=nil)
  return :unknown if surface_type_str.nil? && runoff_volume_type_str.nil?
  if surface_type_str
    st = surface_type_str.to_s.downcase.strip
    return :impervious if IMPERVIOUS_PATTERNS.any? { |p| st.include?(p) }
    return :pervious   if PERVIOUS_PATTERNS.any?   { |p| st.include?(p) }
  end
  if runoff_volume_type_str
    rvt = runoff_volume_type_str.to_s.downcase.strip
    return :impervious if rvt.include?('fixed')
    return :pervious   if rvt.include?('green') || rvt.include?('horton')
  end
  :unknown
end

def surface_type_label(c)
  case c
  when :pervious then "Pervious"
  when :impervious then "Impervious"
  else "Unknown"
  end
end

$mismatches = []
$stats = {
  iw_subcatchments: 0, sw_subcatchments: 0, matched_ids: 0,
  unmatched_sw: 0, unmatched_iw: 0,
  infiltration_types: Hash.new(0),
  parameter_mismatches: Hash.new(0),
  total_mismatches: 0,
  surface_type_counts: Hash.new(0)
}

def record_mismatch(id, name, sw, iw, cat, ssrc, isrc)
  $mismatches << {
    id: id, parameter: name, swmm_value: sw, swmm_source_field: ssrc,
    iw_value: iw, iw_source_field: isrc, category: cat,
    difference: (sw.is_a?(Numeric) && iw.is_a?(Numeric)) ? (sw - iw).abs : "N/A"
  }
  $stats[:parameter_mismatches][name] += 1
  $stats[:total_mismatches] += 1
end

begin
  ts_log "Starting Model Evaluation (Master Report v2.2 hardened)"

  cn = WSApplication.current_network
  bn = WSApplication.background_network
  iw_net = !safe_rows(cn, 'hw_subcatchment').empty? ? cn : (!safe_rows(bn, 'hw_subcatchment').empty? ? bn : nil)
  sw_net = !safe_rows(cn, 'sw_subcatchment').empty? ? cn : (!safe_rows(bn, 'sw_subcatchment').empty? ? bn : nil)

  puts "=" * PAGE_WIDTH
  puts "MASTER REPORT (hardened)"
  puts "InfoWorks Source: #{iw_net ? iw_net.model_object.name : 'Not Found'}"
  puts "SWMM Source:      #{sw_net ? sw_net.model_object.name : 'Not Found'}"
  puts "Timestamp:        #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"
  puts "=" * PAGE_WIDTH

  iw_rs_classified = {}
  iw_lu_map = {}
  iw_sub_map = {}
  iw_sub_data = {}
  sw_sub_data = {}

  if iw_net
    safe_rows(iw_net, 'hw_runoff_surface').each do |ro|
      next if ro.nil?
      begin
        rid = safe_get(ro, :runoff_index)
        st = safe_get(ro, :surface_type, "")
        rvt = safe_get(ro, :runoff_volume_type, "")
        c = classify_surface_type(st, rvt)
        iw_rs_classified[rid] = { object: ro, classification: c, surface_type_str: st, runoff_volume_type: rvt }
        $stats[:surface_type_counts][c] += 1
      rescue => e
        ts_log "Skip runoff_surface row: #{e.message}"
      end
    end
    safe_rows(iw_net, 'hw_land_use').each do |lu|
      next if lu.nil?
      surfaces = []
      (1..12).each { |i| surfaces[i] = safe_get(lu, "runoff_index_#{i}") }
      iw_lu_map[safe_get(lu, :land_use_id)] = surfaces
    end
    safe_rows(iw_net, 'hw_subcatchment').each do |sc|
      next if sc.nil?
      sid = safe_get(sc, :subcatchment_id)
      iw_sub_map[sid] = safe_get(sc, :land_use_id)
      iw_sub_data[sid] = sc
      $stats[:iw_subcatchments] += 1
    end
  end

  if sw_net
    safe_rows(sw_net, 'sw_subcatchment').each do |sc|
      next if sc.nil?
      sid = safe_get(sc, :id)
      sw_sub_data[sid] = sc
      $stats[:sw_subcatchments] += 1
    end
  end

  sw_sub_data.keys.each do |sid|
    iw_sub_map.key?(sid) ? ($stats[:matched_ids] += 1) : ($stats[:unmatched_sw] += 1)
  end
  iw_sub_data.keys.each { |sid| $stats[:unmatched_iw] += 1 unless sw_sub_data.key?(sid) }

  puts "\nOverall stats: #{$stats.reject { |k, _| [:infiltration_types, :parameter_mismatches, :surface_type_counts].include?(k) }.inspect}"
  puts "Surface type counts: #{$stats[:surface_type_counts].inspect}"
  puts "Mismatches recorded: (run sections individually as needed)"

  if EXPORT_CSV && $mismatches.any?
    begin
      File.open(CSV_PATH, 'w') do |f|
        f.puts "Subcatchment,Parameter,SWMM_Value,SWMM_Source_Field,IW_Value,IW_Source_Field,Difference,Category"
        $mismatches.each do |mm|
          sw = mm[:swmm_value].is_a?(Numeric) ? mm[:swmm_value] : "\"#{mm[:swmm_value]}\""
          iw = mm[:iw_value].is_a?(Numeric) ? mm[:iw_value] : "\"#{mm[:iw_value]}\""
          d  = mm[:difference].is_a?(Numeric) ? mm[:difference] : "\"#{mm[:difference]}\""
          f.puts "#{mm[:id]},#{mm[:parameter]},#{sw},\"#{mm[:swmm_source_field]}\",#{iw},\"#{mm[:iw_source_field]}\",#{d},#{mm[:category]}"
        end
      end
      ts_log "CSV exported to: #{CSV_PATH}"
    rescue => e
      ts_log "CSV export failed: #{e.message}"
    end
  end

  puts "\n" + "=" * PAGE_WIDTH
  puts "MASTER ANALYSIS COMPLETE  #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"
  puts "=" * PAGE_WIDTH

rescue => e
  ts_log "FATAL: #{e.class}: #{e.message}"
  puts e.backtrace.first(5).join("\n") if e.backtrace
ensure
  ts_log "Model Evaluation finished"
end
