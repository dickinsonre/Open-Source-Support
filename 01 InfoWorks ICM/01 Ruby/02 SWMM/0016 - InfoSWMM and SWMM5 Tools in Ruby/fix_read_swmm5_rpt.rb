# frozen_string_literal: true
# =============================================================================
# fix_read_swmm5_rpt.rb
# =============================================================================
# Purpose:
#   Hardened SWMM5 / InfoSWMM / ICM SWMM RPT parser. Reads selected summary
#   sections from a SWMM5-format report file and writes extracted values to
#   user_number_* / user_text_* fields on sw_conduit and sw_node rows in the
#   current network. Optional auto-selection of nodes/conduits flagged in
#   instability/critical/non-converging summaries.
#
# Inputs:
#   - Current network in EDIT mode (sw_conduit / sw_node)
#   - User selects an RPT file via prompt
#   - Boolean flags choose which sections to parse and whether to select
#
# Outputs:
#   - Field updates on sw_conduit and sw_node rows
#   - Console summary line list
#
# UI vs Exchange: UI script.
#
# Hardening notes:
#   - frozen_string_literal, timestamped logging, begin/rescue/ensure
#   - Validates prompt cancellation, file existence, network presence
#   - Each section parser wrapped in rescue so a single bad block does not
#     abort the rest of the run
#   - Per-line rescue inside each parser; malformed rows are skipped
#   - Transaction committed on success, cancelled on raise
#   - Nil-safe row-object lookup; nil tokens guarded
# =============================================================================

require 'csv'
require 'pathname'

def ts_log(msg)
  puts "[#{Time.now.strftime('%H:%M:%S')}] #{msg}"
end

def parse_section(lines_hash, header_text, skip)
  # Yield each non-empty token-row in the section starting `skip` lines after
  # the header line. Stop at first empty line. Per-row rescue.
  lines_hash.each do |index, line|
    next unless line.start_with?(header_text)
    start_index = index + skip
    while start_index < lines_hash.size
      l = lines_hash[start_index]
      tokens = l.to_s.split
      break if tokens.empty?
      begin
        yield tokens, start_index
      rescue => e
        ts_log "WARNING parsing #{header_text} line #{start_index}: #{e.message}"
      end
      start_index += 1
    end
    break
  end
end

def select_file
  ts_log "Starting SWMM5 RPT reader"

  cn = WSApplication.current_network
  raise "No current network." if cn.nil?

  result = WSApplication.prompt "InfoSWMM, SWMM5 or ICM SWMM RPT File",
  [
    ['RPT File, SWMM5 Sections will be Read', 'String', nil, nil, 'FILE', true, '*.*', 'rpt', false],
    ['Raingage Summary','Boolean',false],
    ['Subcatchment Summary', 'Boolean',true],
    ['Node Summary', 'Boolean',true],
    ['Link Summary', 'Boolean',true],
    ['Cross Section Summary', 'Boolean',true],
    ['Highest Continuity Errors', 'Boolean',true],
    ['Time-Step Critical Elements', 'Boolean',true],
    ['Highest Flow Instability Indexes','Boolean',true],
    ['Most Frequent Nonconverging Nodes', 'Boolean',true],
    ['Routing Time Step Summary', 'Boolean',false],
    ['Subcatchment Runoff Summary', 'Boolean',true],
    ['Node Depth Summary', 'Boolean',true],
    ['Node Inflow Summary', 'Boolean',true],
    ['Node Surcharge Summary', 'Boolean',true],
    ['Node Flooding Summary', 'Boolean',true],
    ['Outfall Loading Summary', 'Boolean',true],
    ['Link Flow Summary', 'Boolean',true],
    ['Flow Classification Summary','Boolean',true],
    ['Conduit Surcharge Summary','Boolean',true]
  ], false

  if result.nil?
    ts_log "User cancelled."
    return
  end

  file_path = result[0]
  raise "No file path." if file_path.nil? || file_path.empty?
  raise "File does not exist: #{file_path}" unless File.exist?(file_path)
  ts_log "RPT: #{file_path}"

  cn.transaction_begin
  begin
    ro_hash = {}
    cn.row_objects('sw_conduit').each { |ro| ro_hash[ro.id] = ro if ro }
    rn_hash = {}
    cn.row_objects('sw_node').each { |ro| rn_hash[ro.id] = ro if ro }

    lines_hash = {}
    File.foreach(file_path, encoding: 'bom|utf-8') do |raw|
      lines_hash[lines_hash.size] = raw.strip
    end
    ts_log "Read #{lines_hash.size} lines"

    # Cross Section Summary
    begin
      parse_section(lines_hash, "Cross Section Summary", 5) do |tokens, _|
        next if tokens.size < 8
        id = tokens[0]
        ro = ro_hash[id]
        next unless ro
        ro.user_number_1 = tokens[2].to_f
        ro.user_number_2 = tokens[7].to_f
        ro.user_number_8 = tokens[3]
        ro.user_number_9 = tokens[4]
        ro.write
      end
    rescue => e
      ts_log "Section error (Cross Section): #{e.message}"
    end

    # Link Summary
    begin
      parse_section(lines_hash, "Link Summary", 4) do |tokens, _|
        next if tokens.size < 6
        ro = ro_hash[tokens[0]]
        next unless ro
        ro.user_number_3 = tokens[5].to_f
        ro.write
      end
    rescue => e
      ts_log "Section error (Link Summary): #{e.message}"
    end

    # Node Summary
    begin
      parse_section(lines_hash, "Node Summary", 5) do |tokens, _|
        next if tokens.size < 6
        rn = rn_hash[tokens[0]]
        next unless rn
        rn.user_number_1 = tokens[3].to_f
        rn.user_number_2 = tokens[2].to_f
        rn.write
      end
    rescue => e
      ts_log "Section error (Node Summary): #{e.message}"
    end

    # Node Depth Summary
    begin
      parse_section(lines_hash, "Node Depth Summary", 7) do |tokens, _|
        next if tokens.size < 10
        rn = rn_hash[tokens[0]]
        next unless rn
        rn.user_number_3 = tokens[3].to_f
        rn.user_number_4 = tokens[4].to_f
        rn.user_number_5 = tokens[7].to_f
        rn.user_text_6   = "#{tokens[5]}   #{tokens[6]}"
        rn.user_text_7   = "#{tokens[8]}   #{tokens[9]}"
        rn.write
      end
    rescue => e
      ts_log "Section error (Node Depth Summary): #{e.message}"
    end

    # Node Inflow Summary
    begin
      parse_section(lines_hash, "Node Inflow Summary", 7) do |tokens, _|
        next if tokens.size < 10
        rn = rn_hash[tokens[0]]
        next unless rn
        rn.user_number_6 = tokens[2].to_f
        rn.user_number_7 = tokens[3].to_f
        rn.user_number_8 = tokens[6].to_f
        rn.user_number_9 = tokens[7].to_f
        rn.write
      end
    rescue => e
      ts_log "Section error (Node Inflow Summary): #{e.message}"
    end

    # Node Surcharge Summary
    begin
      parse_section(lines_hash, "Node Surcharge Summary", 9) do |tokens, _|
        next if tokens.size < 10
        rn = rn_hash[tokens[0]]
        next unless rn
        rn.user_number_10 = tokens[2].to_f
        rn.user_text_1 = tokens[3].to_s
        rn.user_text_2 = tokens[4].to_s
        rn.write
      end
    rescue => e
      ts_log "Section error (Node Surcharge Summary): #{e.message}"
    end

    # Node Flooding Summary
    begin
      parse_section(lines_hash, "Node Flooding Summary", 9) do |tokens, _|
        next if tokens.size < 10
        rn = rn_hash[tokens[0]]
        next unless rn
        rn.user_text_3 = tokens[1].to_s
        rn.user_text_4 = tokens[2].to_s
        rn.user_text_5 = tokens[5].to_s
        rn.user_text_8 = "#{tokens[3]}   #{tokens[4]}"
        rn.write
      end
    rescue => e
      ts_log "Section error (Node Flooding Summary): #{e.message}"
    end

    # Outfall Loading Summary
    begin
      parse_section(lines_hash, "Outfall Loading Summary", 7) do |tokens, _|
        next if tokens.size < 10
        rn = rn_hash[tokens[0]]
        next unless rn
        rn.user_text_9  = tokens[3].to_s
        rn.user_text_10 = tokens[4].to_s
        rn.write
      end
    rescue => e
      ts_log "Section error (Outfall Loading Summary): #{e.message}"
    end

    # Link Flow Summary
    begin
      parse_section(lines_hash, "Link Flow Summary", 8) do |tokens, _|
        next if tokens.size < 13
        ro = ro_hash[tokens[0]]
        next unless ro
        ro.user_number_4 = tokens[2].to_f
        ro.user_text_1 = "#{tokens[3]}   #{tokens[4]}"
        token9 = tokens[9]
        token9 = '50.00' if token9 == '>50.00'
        ro.user_number_5 = token9.to_f
        ro.user_number_6 = tokens[8].to_f
        ro.user_number_7 = tokens[12].to_f
        ro.write
      end
    rescue => e
      ts_log "Section error (Link Flow Summary): #{e.message}"
    end

    # Conduit Surcharge Summary
    begin
      parse_section(lines_hash, "Conduit Surcharge Summary", 8) do |tokens, _|
        next if tokens.size < 6
        ro = ro_hash[tokens[0]]
        next unless ro
        ro.user_text_2 = tokens[1].to_s
        ro.user_text_3 = tokens[2].to_s
        ro.user_text_4 = tokens[3].to_s
        ro.user_text_5 = tokens[4].to_s
        ro.user_text_6 = tokens[5].to_s
        ro.write
      end
    rescue => e
      ts_log "Section error (Conduit Surcharge Summary): #{e.message}"
    end

    # Time-Step Critical Elements
    begin
      parse_section(lines_hash, "Time-Step Critical Elements", 3) do |tokens, _|
        next if tokens.size < 4
        percent = tokens[2].to_s.gsub(/[()%]/, '').to_f
        ro = ro_hash[tokens[1]]
        rn = rn_hash[tokens[1]]
        if result[7] && percent > 0.5
          ro.selected = true if ro
          rn.selected = true if rn
        end
      end
    rescue => e
      ts_log "Section error (Time-Step Critical): #{e.message}"
    end

    # Highest Flow Instability Indexes
    begin
      parse_section(lines_hash, "Highest Flow Instability Indexes", 3) do |tokens, _|
        next if tokens.size < 4
        percent = tokens[2].to_s.gsub(/[()%]/, '').to_i
        ro = ro_hash[tokens[1]]
        if ro && result[8] && percent > 0
          ro.selected = true
        end
      end
    rescue => e
      ts_log "Section error (Flow Instability): #{e.message}"
    end

    # Highest Continuity Errors
    begin
      parse_section(lines_hash, "Highest Continuity Errors", 3) do |tokens, _|
        next if tokens.size < 4
        rn = rn_hash[tokens[1]]
        rn.selected = true if rn && result[6]
      end
    rescue => e
      ts_log "Section error (Continuity Errors): #{e.message}"
    end

    # Most Frequent Nonconverging Nodes
    begin
      parse_section(lines_hash, "Most Frequent Nonconverging Nodes", 3) do |tokens, _|
        next if tokens.size < 4
        rn = rn_hash[tokens[1]]
        rn.selected = true if rn && result[9]
      end
    rescue => e
      ts_log "Section error (Nonconverging): #{e.message}"
    end

    # Flow Classification Summary
    begin
      parse_section(lines_hash, "Flow Classification Summary", 8) do |tokens, _|
        next if tokens.size < 10
        ro = ro_hash[tokens[0]]
        next unless ro
        ro.user_number_10 = tokens[1]
        ro.user_text_7 = tokens[2].to_s
        ro.user_text_8 = tokens[5].to_s
        ro.user_text_9 = tokens[6].to_s
        ro.user_text_10 = tokens[9].to_s
        ro.write
      end
    rescue => e
      ts_log "Section error (Flow Classification): #{e.message}"
    end

    summary_lines = lines_hash.select do |_, line|
      line.include?("Summary") || line.include?("Critical") || line.include?("Highest") || line.include?("Most Frequent")
    end
    puts ""
    ts_log "Summary or Information Tables: #{summary_lines.size}"
    summary_lines.each { |_, line| puts line.slice(0, 99) }

    cn.transaction_commit
    ts_log "Transaction committed - script finished successfully."

  rescue => e
    cn.transaction_cancel rescue nil
    raise
  end
end

begin
  select_file
rescue => e
  ts_log "FATAL: #{e.class}: #{e.message}"
  puts e.backtrace.first(5).join("\n") if e.backtrace
ensure
  ts_log "RPT reader run finished"
end
