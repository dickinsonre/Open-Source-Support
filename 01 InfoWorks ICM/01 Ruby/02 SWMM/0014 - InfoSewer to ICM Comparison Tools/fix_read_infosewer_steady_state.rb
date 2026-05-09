# frozen_string_literal: true
# =============================================================================
# fix_read_infosewer_steady_state.rb
# =============================================================================
# Purpose:
#   Hardened parser for an InfoSewer steady-state RPT file. Reads section
#   blocks (Loading Manholes, Pipes, Force Mains, Pumps, Summary) and prints
#   per-section column statistics plus CSV-style output blocks.
#
# Inputs:
#   - User selects an RPT file via prompt
#   - Booleans for which sections to process
#
# Outputs:
#   - Console statistics table
#   - Console CSV blocks for Loading Manholes and combined links
#
# UI vs Exchange:
#   UI script - uses WSApplication.prompt.
#
# Hardening notes:
#   - frozen_string_literal + timestamped progress logging
#   - Validates prompt cancellation, file existence, and per-line parse
#   - Per-line rescue so malformed rows don't crash the run
#   - File access uses File.foreach (streaming, low memory)
#   - Begin/rescue/ensure wraps the whole script
# =============================================================================

require 'pathname'

def ts_log(msg)
  puts "[#{Time.now.strftime('%H:%M:%S')}] #{msg}"
end

begin
  ts_log "Starting InfoSewer Steady State RPT reader"

  result = WSApplication.prompt "Reading the InfoSewer Steady State RPT File",
  [
    ['RPT File', 'String', nil, nil, 'FILE', true, '*.*', 'rpt', false],
    ['[Summary]', 'Boolean', true],
    ['[Loading Manholes]', 'Boolean', true],
    ['[Pipes]', 'Boolean', true],
    ['[Force Mains]', 'Boolean', true],
    ['[Pumps]', 'Boolean', true]
  ], false

  if result.nil?
    ts_log "User cancelled the dialog."
    return
  end

  file_path = result[0]
  raise "No file path provided." if file_path.nil? || file_path.empty?
  raise "File does not exist: #{file_path}" unless File.exist?(file_path)
  ts_log "Selected RPT File: #{file_path}"

  process_section_flags = {
    'Summary'          => result[1],
    'Loading Manholes' => result[2],
    'Pipes'            => result[3],
    'Force Mains'      => result[4],
    'Pumps'            => result[5]
  }

  loading_manhole_headers = ['Base', 'Storm', 'Total']
  pumps_headers = ['Pump Count', 'Pump Flow', 'Pump Head']
  force_mains_headers = ['Pipe Diam', 'Pipe Flow', 'Pipe Vel.', 'Pipe Loss']
  pipe_headers = [
    'Pipe Count', 'Pipe Slope', 'Pipe Diam', 'Pipe Flow 1', 'Pipe Load',
    'Pipe Flow 2', 'Pipe Flow 3', 'Pipe Flow 4', 'Pipe Flow 5', 'Pipe Veloc',
    'Pipe d/D', 'Pipe Depth 1', 'Pipe Number', 'Pipe Depth 2', 'Pipe Flow 6',
    'Cover Count'
  ]

  sections = {}
  current_section_name = nil
  line_counter = 0
  bad_lines = 0

  File.foreach(file_path, encoding: 'bom|utf-8') do |raw|
    begin
      line = raw.gsub('Exponential 3-Point', 'Exponential3-Point')
      line.strip!
      next if line.empty?

      if line.start_with?('[') && line.end_with?(']')
        potential = line[1..-2]
        if process_section_flags[potential] || potential == 'Title'
          current_section_name = potential
          sections[current_section_name] = {}
        else
          current_section_name = nil
        end
        line_counter = 0
        next
      end

      if current_section_name && sections.key?(current_section_name) && line_counter >= 3
        tokens = line.split
        next if tokens.empty?
        id = tokens.shift
        next unless id

        case current_section_name
        when 'Pipes'       then 2.times { tokens.shift unless tokens.empty? }
        when 'Force Mains' then 2.times { tokens.shift unless tokens.empty? }
        when 'Pumps'       then 3.times { tokens.shift unless tokens.empty? }
        end

        numerical_values = tokens.map do |t|
          begin
            Float(t)
          rescue ArgumentError, TypeError
            nil
          end
        end
        sections[current_section_name][id] = numerical_values
      end

      line_counter += 1 if current_section_name
    rescue => e
      bad_lines += 1
      ts_log "Skipped malformed line: #{e.message}"
    end
  end

  ts_log "Parse complete. Sections: #{sections.keys.inspect}, malformed lines skipped: #{bad_lines}"

  puts "\n--- Statistical Summary ---"
  sections.each do |section_name, ids_data|
    next if ['Title', 'Summary'].include?(section_name)
    next unless process_section_flags.fetch(section_name, false) && !ids_data.empty?

    puts "\nSection: #{section_name}"
    headers = case section_name
              when 'Loading Manholes' then loading_manhole_headers
              when 'Pumps'            then pumps_headers
              when 'Force Mains'      then force_mains_headers
              when 'Pipes'            then pipe_headers
              end
    next if headers.nil?

    headers.each_with_index do |header, index|
      vals = ids_data.values.map { |row| row[index] if row && row.size > index && !row[index].nil? }.compact
      mean_val, max_val, min_val = 0.0, 0.0, 0.0
      count_val = vals.size
      if count_val > 0
        mean_val = vals.sum / count_val.to_f
        max_val = vals.max
        min_val = vals.min
      end
      printf "  %-20s | Mean: %-15.3f | Max: %-15.3f | Min: %-15.3f | Count: %-10d\n",
             header, mean_val, max_val, min_val, count_val
    end
  end

  puts "\n--- CSV Output: Loading Manholes ---"
  if process_section_flags['Loading Manholes'] && sections['Loading Manholes'] && !sections['Loading Manholes'].empty?
    puts "ID,Base,Storm,Total"
    sections['Loading Manholes'].each do |id, vals|
      puts "#{id},#{vals[0] || 0.0},#{vals[1] || 0.0},#{vals[2] || 0.0}"
    end
  else
    puts "No Loading Manholes data to display"
  end

  puts "\n--- CSV Output: Links (Pipes, Force Mains, Pumps) ---"
  link_data = []
  if process_section_flags['Pipes'] && sections['Pipes']
    sections['Pipes'].each do |id, v|
      link_data << { id: id, type: 'Pipe', diameter: v[2] || 0.0, flow: v[3] || 0.0, velocity: v[9] || 0.0, depth_ratio: v[10] || 0.0 }
    end
  end
  if process_section_flags['Force Mains'] && sections['Force Mains']
    sections['Force Mains'].each do |id, v|
      link_data << { id: id, type: 'Force Main', diameter: v[0] || 0.0, flow: v[1] || 0.0, velocity: v[2] || 0.0, depth_ratio: 1.0 }
    end
  end
  if process_section_flags['Pumps'] && sections['Pumps']
    sections['Pumps'].each do |id, v|
      link_data << { id: id, type: 'Pump', diameter: 0.0, flow: v[1] || 0.0, velocity: 0.0, depth_ratio: 0.0 }
    end
  end

  if link_data.any?
    puts "ID,Type,Diameter,Flow,Velocity,Depth_Ratio"
    link_data.each { |l| puts "#{l[:id]},#{l[:type]},#{l[:diameter]},#{l[:flow]},#{l[:velocity]},#{l[:depth_ratio]}" }
  else
    puts "No link data to display"
  end

rescue => e
  ts_log "FATAL: #{e.class}: #{e.message}"
  puts e.backtrace.first(5).join("\n") if e.backtrace
ensure
  ts_log "Steady-state RPT reader finished"
end
