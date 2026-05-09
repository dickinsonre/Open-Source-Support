# frozen_string_literal: true
# =============================================================================
# fix_ICM InfoWorks vs ICM SWMM Subcatchment.rb
# =============================================================================
# Purpose:
#   Hardened diagnostic that lists tables in the current and background
#   networks and counts hw_subcatchment / sw_subcatchment row objects to
#   support InfoWorks vs ICM SWMM comparison investigations.
#
# Inputs:
#   - WSApplication.current_network (InfoWorks)
#   - WSApplication.background_network (ICM SWMM)
#
# Outputs: Console diagnostic report.
#
# UI vs Exchange: UI script.
#
# Hardening notes:
#   - frozen_string_literal, timestamped logging
#   - begin/rescue/ensure top-level
#   - nil-safe network checks; per-iteration rescue when listing tables
# =============================================================================

def ts_log(msg)
  puts "[#{Time.now.strftime('%H:%M:%S')}] #{msg}"
end

def list_tables(net, label)
  puts "AVAILABLE TABLES IN #{label}:"
  puts "-" * 80
  if net.nil?
    puts "  Network not available."
    return
  end
  begin
    table_names = net.tables.map { |t| t.name }.sort
    puts "  Found #{table_names.count} tables. First 5: #{table_names.first(5).join(', ')}..."
  rescue => e
    puts "  Error listing tables: #{e.message}"
  end
end

begin
  ts_log "Starting InfoWorks vs SWMM diagnostic"

  cn = WSApplication.current_network
  bn = WSApplication.background_network
  puts "Current Network:    #{cn ? cn.model_object.name : '[None]'}"
  puts "Background Network: #{bn ? bn.model_object.name : '[None]'}"
  puts "=" * 100

  list_tables(cn, "CURRENT NETWORK")
  puts ""
  list_tables(bn, "BACKGROUND NETWORK")
  puts ""

  puts "ATTEMPTING TO ACCESS sw_subcatchment IN BACKGROUND NETWORK:"
  if bn
    count = 0
    begin
      bn.row_objects('sw_subcatchment').each do |sc|
        next if sc.nil?
        count += 1
        puts "  Found SWMM ID: #{sc.id}" if count <= 3
      end
      puts "  Total sw_subcatchment count: #{count}"
    rescue => e
      puts "  ERROR: #{e.message}"
    end
  else
    puts "  Background network is nil. Skipped."
  end
  puts ""

  puts "ATTEMPTING TO ACCESS hw_subcatchment IN CURRENT NETWORK:"
  if cn
    count = 0
    begin
      cn.row_objects('hw_subcatchment').each do |sc|
        next if sc.nil?
        count += 1
        puts "  Found InfoWorks ID: #{sc.subcatchment_id}" if count <= 3
      end
      puts "  Total hw_subcatchment count: #{count}"
    rescue => e
      puts "  ERROR: #{e.message}"
    end
  else
    puts "  Current network is nil. Skipped."
  end

  puts "\n" + "=" * 100
  puts "Diagnostic Complete"
rescue => e
  ts_log "FATAL: #{e.class}: #{e.message}"
  puts e.backtrace.first(5).join("\n") if e.backtrace
ensure
  ts_log "Diagnostic finished"
end
