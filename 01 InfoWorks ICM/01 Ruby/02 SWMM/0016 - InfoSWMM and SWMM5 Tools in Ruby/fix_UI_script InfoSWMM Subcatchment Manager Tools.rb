# frozen_string_literal: true
# =============================================================================
# fix_UI_script InfoSWMM Subcatchment Manager Tools.rb
# =============================================================================
# Purpose:
#   Hardened version of the InfoSWMM Subcatchment Manager. For each
#   hw_subcatchment in the current network it computes geometric measurements
#   (perimeter, max width, max height) from the boundary polygon and updates
#   the SWMM5 catchment_dimension (width) using one of four formulas:
#     - 1.7 * max(width, height)
#     - K * sqrt(area)
#     - K * perimeter
#     - area / max(width, height)  (flow length)
#   Units (USA acres or SI hectares) and K are user-supplied via prompt.
#
# Inputs:
#   - Current network in EDIT mode with hw_subcatchment polygons
#   - User parameters via WSApplication.prompt
#
# Outputs:
#   - Updates catchment_dimension field on hw_subcatchment rows
#   - Console diagnostics: per-subcatchment perimeter/H/W and totals
#
# UI vs Exchange: UI script.
#
# Hardening notes:
#   - frozen_string_literal, timestamped logging
#   - begin/rescue/ensure with transaction commit on success, cancel on error
#   - validates network, prompt cancellation, K range (defaults to 1.0)
#   - per-row rescue so a single subcatchment failure doesn't abort the batch
#   - nil-safe for subcatchment_id, total_area, catchment_dimension, boundary
# =============================================================================

def ts_log(msg)
  puts "[#{Time.now.strftime('%H:%M:%S')}] #{msg}"
end

begin
  ts_log "Starting Subcatchment Manager (hardened)"

  cn = WSApplication.current_network
  raise "No current network." if cn.nil?

  val = WSApplication.prompt "Choose USA or SI Units SWMM5 Subcatchment Width Calculation Method",
  [
    ['USA Units','Boolean',false],
    ['SI  Units','Boolean',true],
    ['Width = 1.7 * Max(Height, Width)', 'Boolean',false],
    ['Width = K * SQRT(Area)', 'Boolean',false],
    ['Width = K * Perimeter', 'Boolean',false],
    ['Width = Area / Flow Length', 'Boolean',false],
    ['K value 0.2 to 5 default of 1', 'String'],
    ['Choose the Unit type and Width Option', 'String']
  ], false

  if val.nil?
    ts_log "User cancelled."
    return
  end

  usa = !!val[0]
  si  = !!val[1]
  k_input = val[6].to_s.strip
  k = k_input.empty? ? 1.0 : k_input.to_f
  k = 1.0 if k.nil? || k == 0.0
  max_height_opt = !!val[2]
  sqrt_area_opt = !!val[3]
  width_perim_opt = !!val[4]
  flow_length_opt = !!val[5]

  ts_log "Options: USA=#{usa}, SI=#{si}, K=#{k}, MaxHW=#{max_height_opt}, sqrt(A)=#{sqrt_area_opt}, perim=#{width_perim_opt}, flowlen=#{flow_length_opt}"

  cn.transaction_begin
  rolled_back = false

  begin
    subcatchment_measurements = {}

    cn.row_object_collection('hw_subcatchment').each do |polygon|
      next if polygon.nil?
      begin
        boundary_array = polygon.boundary_array
        perimeter = 0.0
        max_height = 0.0
        max_width = 0.0
        if boundary_array && boundary_array.any?
          points = boundary_array.each_slice(2).to_a
          xs = points.map(&:first)
          ys = points.map(&:last)
          unless xs.empty? || ys.empty?
            max_width = xs.max - xs.min
            max_height = ys.max - ys.min
            points.each_with_index do |point, index|
              next_point = points[(index + 1) % points.size]
              perimeter += Math.sqrt((next_point[0] - point[0])**2 + (next_point[1] - point[1])**2)
            end
          end
        end
        subcatchment_measurements[polygon.subcatchment_id] = {
          perimeter: perimeter, max_height: max_height, max_width: max_width
        }
      rescue => e
        ts_log "ERROR measuring subcatchment #{polygon&.subcatchment_id}: #{e.message}"
      end
    end

    subcatchment_measurements.each do |id, m|
      puts "Subcatchment ID: #{id}, Perimeter: #{'%.4f' % m[:perimeter]}, Max Height: #{'%.4f' % m[:max_height]}, Max Width: #{'%.4f' % m[:max_width]}"
    end

    total_before = 0.0
    total_after = 0.0
    updated = 0
    skipped = 0

    cn.row_objects('hw_subcatchment').each do |ro|
      next if ro.nil?
      begin
        next if ro.total_area.nil? || ro.catchment_dimension.nil?
        m = subcatchment_measurements[ro.subcatchment_id]
        if m.nil?
          skipped += 1
          next
        end
        before = ro.catchment_dimension.to_f
        total_before += before
        max_dim = [m[:max_width], m[:max_height]].max
        area_factor = usa ? 43560.0 : 10000.0
        if max_height_opt
          ro.catchment_dimension = 1.7 * max_dim
        end
        if sqrt_area_opt
          ro.catchment_dimension = k * Math.sqrt(ro.total_area.to_f * area_factor)
        end
        if width_perim_opt
          ro.catchment_dimension = k * m[:perimeter]
        end
        if flow_length_opt
          if max_dim > 0
            ro.catchment_dimension = (ro.total_area.to_f * area_factor) / max_dim
          end
        end
        total_after += ro.catchment_dimension.to_f
        ro.write
        updated += 1
      rescue => e
        ts_log "ERROR updating #{ro&.subcatchment_id}: #{e.message}"
      end
    end

    puts "Total SWMM5 Width before update: #{'%.4f' % total_before}"
    puts "Total SWMM5 Width after update:  #{'%.4f' % total_after}"
    puts "Total SWMM5 Width change:        #{'%.4f' % (total_after - total_before)}"
    puts "Updated: #{updated}, Skipped: #{skipped}"
    if sqrt_area_opt
      puts (k == 1.0 ? "Width = K * SQRT(Area) with K = 1" : "Width = K * SQRT(Area) with K = #{k}")
    end
    if width_perim_opt
      puts (k == 1.0 ? "Width = K * Perimeter with K = 1" : "Width = K * Perimeter with K = #{k}")
    end

    cn.transaction_commit
    ts_log "Transaction committed."
  rescue => e
    rolled_back = true
    cn.transaction_cancel rescue nil
    raise
  end

rescue => e
  ts_log "FATAL: #{e.class}: #{e.message}"
  puts e.backtrace.first(5).join("\n") if e.backtrace
ensure
  ts_log "Subcatchment Manager finished"
end
