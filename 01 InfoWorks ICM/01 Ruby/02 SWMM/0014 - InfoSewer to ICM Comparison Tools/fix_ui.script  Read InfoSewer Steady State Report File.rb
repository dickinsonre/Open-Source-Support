# frozen_string_literal: true
# =============================================================================
# fix_ui.script  Read InfoSewer Steady State Report File.rb
# =============================================================================
# Purpose:
#   Hardened batch parser for InfoSewer RPT (steady-state) files. The user
#   selects any file in the target folder; the script discovers every *.rpt
#   nearby, parses each, computes per-file and aggregate statistics across
#   Loading Manholes / Pipes / Force Mains / Pumps, and exports CSV results.
#
# Inputs:
#   - User-selected RPT file (any file in the target folder works)
#   - Booleans: include subdirectories, export CSVs, show per-file stats,
#     show aggregate stats
#
# Outputs:
#   - Console reports
#   - When export_csv: CSV files in <start_dir>/RPT_Analysis_<timestamp>/
#
# UI vs Exchange:
#   UI script - uses WSApplication.prompt and message_box.
#
# Hardening notes:
#   - frozen_string_literal + timestamped progress logging
#   - Validates prompt cancellation, file/folder existence
#   - Each File.foreach wrapped in rescue (malformed lines skipped)
#   - CSV.open with block form for guaranteed close
#   - Each export block isolated by rescue so one failure doesn't abort others
#   - Top-level begin/rescue/ensure
# =============================================================================

require 'csv'

def ts_log(msg)
  puts "[#{Time.now.strftime('%H:%M:%S')}] #{msg}"
end

def find_rpt_files_from_roots(roots, include_subdirs)
  patterns = []
  roots.uniq.each do |root|
    next unless root && Dir.exist?(root)
    if include_subdirs
      patterns << File.join(root, '**', '*.{rpt,RPT}')
    else
      patterns << File.join(root, '*.{rpt,RPT}')
    end
  end
  patterns.flat_map { |p| Dir.glob(p, File::FNM_CASEFOLD) }.uniq
end

def calculate_stats(vals)
  return [0, 0.0, 0.0, 0.0, 0.0] if vals.nil? || vals.empty?
  n = vals.size.to_f
  mean = vals.sum / n
  sum_sq = vals.map { |v| (v - mean) ** 2 }.sum
  std = (n > 1) ? Math.sqrt(sum_sq / (n - 1)) : 0.0
  [vals.size, mean, std, vals.min, vals.max]
end

def stats_row(vals)
  return [0, 0, 0, 0, 0, 0, 0, 0, 0] if vals.nil? || vals.empty?
  n, mean, std, min, max = calculate_stats(vals)
  sorted = vals.sort
  p25 = sorted[(sorted.size * 0.25).floor]
  p50 = sorted[(sorted.size * 0.50).floor]
  p75 = sorted[(sorted.size * 0.75).floor]
  p95 = sorted[(sorted.size * 0.95).floor]
  [n, mean.round(3), std.round(3), min.round(3), p25.round(3), p50.round(3), p75.round(3), p95.round(3), max.round(3)]
end

begin
  ts_log "Starting Batch RPT Analysis"

  cn = WSApplication.current_network rescue nil

  result = WSApplication.prompt(
    "Batch RPT Analysis - Select ANY RPT file (or any file) in/near the target directory",
    [
      ['Pick an RPT file (or any file in the folder you want to scan)', 'String', nil, nil, 'FILE', true, 'RPT Files|*.rpt|All Files|*.*', 'rpt', false],
      ['=== OPTIONS ===', 'READONLY', ''],
      ['Include subdirectories?', 'Boolean', true],
      ['Export combined CSV?', 'Boolean', true],
      ['Show per-file stats?', 'Boolean', false],
      ['Show aggregate stats?', 'Boolean', true]
    ], false
  )

  if result.nil?
    ts_log "User cancelled."
    return
  end

  selected_path = result[0]
  if selected_path.nil? || selected_path.empty?
    WSApplication.message_box("No file selected.", "OK", "!", false)
    return
  end
  unless File.exist?(selected_path)
    WSApplication.message_box("Selected path does not exist:\n#{selected_path}", "OK", "!", false)
    return
  end

  include_subdirs = !!result[2]
  export_csv      = !!result[3]
  show_per_file   = !!result[4]
  show_aggregate  = !!result[5]

  start_dir = File.directory?(selected_path) ? selected_path : File.dirname(selected_path)

  puts "\n" + "=" * 80
  puts "BATCH RPT FILE ANALYSIS (hardened)"
  puts "=" * 80
  ts_log "Selected: #{selected_path}"
  ts_log "Start dir: #{start_dir}, subdirs=#{include_subdirs}"

  roots = []
  roots << start_dir
  roots << File.expand_path('..', start_dir)
  roots << File.expand_path('../..', start_dir)
  path_parts = start_dir.split(/[\\\/]/)
  out_index = path_parts.index { |s| s =~ /\.out\z/i }
  if out_index
    project_name = path_parts[out_index].sub(/\.out\z/i, '')
    parent_of_out = File.join(*path_parts[0...out_index])
    project_sibling = (parent_of_out.nil? || parent_of_out.empty?) ? project_name : File.join(parent_of_out, project_name)
    roots << project_sibling
    roots << File.join(project_sibling, 'Reports')
  end

  rpt_files = find_rpt_files_from_roots(roots, include_subdirs)
  if rpt_files.empty?
    msg = "No RPT file found.\n\nRoots searched:\n- " + roots.uniq.join("\n- ")
    WSApplication.message_box(msg, "OK", "!", false)
    return
  end
  ts_log "Found #{rpt_files.size} RPT file(s)"

  section_headers = {
    'Loading Manholes' => ['Base', 'Storm', 'Total'],
    'Pumps'            => ['Pump Count', 'Pump Flow', 'Pump Head'],
    'Force Mains'      => ['Pipe Diam', 'Pipe Flow', 'Pipe Vel.', 'Pipe Loss'],
    'Pipes'            => ['Pipe Count', 'Pipe Slope', 'Pipe Diam', 'Pipe Flow', 'Pipe Load',
                           'UnPeak Flow', 'Peak Flow', 'Cover Flow', 'I/I Flow', 'Flow Veloc',
                           'Pipe d/D', 'Actual Depth', 'Flow Number', 'Froude Crit', 'Depth Full',
                           'Flow Cover']
  }
  columns_to_skip = { 'Pipes' => 2, 'Force Mains' => 2, 'Pumps' => 3 }

  all_files_data = []
  rpt_files.each_with_index do |file_path, idx|
    ts_log "[#{idx+1}/#{rpt_files.size}] #{file_path}"
    file_data = { path: file_path, relative_path: file_path, sections: {} }
    current_section = nil
    bad_lines = 0
    begin
      File.foreach(file_path, encoding: 'bom|utf-8') do |raw|
        begin
          line = raw.gsub('Exponential 3-Point', 'Exponential3-Point').strip
          next if line.empty?
          if line.start_with?('[') && line.end_with?(']')
            current_section = line[1..-2]
            file_data[:sections][current_section] ||= {}
            next
          end
          headers = section_headers[current_section]
          next unless current_section && headers
          tokens = line.split
          next if tokens.empty?
          num_expected = headers.size
          skip_cols = columns_to_skip[current_section] || 0
          num_to_grab = num_expected + skip_cols
          next if tokens.size < num_to_grab + 1
          data_tokens = tokens.last(num_to_grab)
          id_tokens = tokens.first(tokens.size - num_to_grab)
          id = id_tokens.join(' ')
          skip_cols.times { data_tokens.shift unless data_tokens.empty? }
          values = data_tokens.map { |t| (Float(t) rescue nil) }
          if !id.empty? && values.size == num_expected && !values.any?(&:nil?)
            file_data[:sections][current_section][id] = values
          end
        rescue => le
          bad_lines += 1
        end
      end
      ts_log "  bad lines skipped: #{bad_lines}; sections: #{file_data[:sections].keys.join(', ')}"
      all_files_data << file_data
    rescue => e
      ts_log "ERROR reading #{file_path}: #{e.class}: #{e.message}"
    end
  end
  ts_log "#{all_files_data.size} files processed"

  if show_per_file
    all_files_data.each_with_index do |fd, idx|
      puts "\n----- File #{idx+1}: #{fd[:relative_path]} -----"
      fd[:sections].each do |section, items|
        next if section == 'Title' || items.empty?
        headers = section_headers[section]
        next unless headers
        puts "\n  #{section} (#{items.size} items):"
        headers.each_with_index do |h, ci|
          vals = items.values.map { |r| r[ci] if r && r[ci] }.compact
          next if vals.empty?
          n, mean, std, min, max = calculate_stats(vals)
          printf "    %-20s | n=%-6d mean=%-10.3f std=%-10.3f min=%-10.3f max=%-10.3f\n", h, n, mean, std, min, max
        end
      end
    end
  end

  aggregate = {}
  all_files_data.each do |fd|
    fd[:sections].each do |section, items|
      next if section == 'Title'
      aggregate[section] ||= {}
      items.each do |id, values|
        aggregate[section][id] ||= []
        aggregate[section][id] << values
      end
    end
  end

  if show_aggregate
    aggregate.each do |section, items|
      next if items.empty?
      headers = section_headers[section]
      next unless headers
      puts "\n----- #{section} (#{items.size} unique items) -----"
      headers.each_with_index do |h, ci|
        all_vals = []
        items.each_value { |arrs| arrs.each { |row| all_vals << row[ci] if row && row[ci] } }
        next if all_vals.empty?
        n, mean, std, min, max = calculate_stats(all_vals)
        sorted = all_vals.sort
        p25 = sorted[(sorted.size * 0.25).floor]
        p50 = sorted[(sorted.size * 0.50).floor]
        p75 = sorted[(sorted.size * 0.75).floor]
        p95 = sorted[(sorted.size * 0.95).floor]
        printf "  %-20s | n=%-6d mean=%-8.3f std=%-8.3f min=%-8.3f 25%%=%-8.3f med=%-8.3f 75%%=%-8.3f 95%%=%-8.3f max=%-8.3f\n",
               h, n, mean, std, min, p25, p50, p75, p95, max
      end
    end
  end

  if export_csv
    timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
    output_dir = File.join(start_dir, "RPT_Analysis_#{timestamp}")
    begin
      Dir.mkdir(output_dir)
    rescue
      output_dir = start_dir
    end
    ts_log "CSV output dir: #{output_dir}"

    # Manholes
    begin
      manhole_file = File.join(output_dir, "nodes_manholes_#{timestamp}.csv")
      CSV.open(manhole_file, "wb") do |csv|
        csv << ["Source File", "Manhole ID", "Base Flow", "Storm Load", "Total Flow"]
        all_files_data.each do |fd|
          next unless fd[:sections]['Loading Manholes']
          fd[:sections]['Loading Manholes'].each do |id, vals|
            csv << [fd[:relative_path], id, vals[0] || 0.0, vals[1] || 0.0, vals[2] || 0.0]
          end
        end
      end
      ts_log "Exported: #{File.basename(manhole_file)}"
    rescue => e
      ts_log "ERROR exporting nodes: #{e.message}"
    end

    # Links
    begin
      links_file = File.join(output_dir, "links_all_#{timestamp}.csv")
      CSV.open(links_file, "wb") do |csv|
        csv << ["Source File", "Link ID", "Link Type", "Diameter", "Flow", "Velocity", "Depth Ratio", "Slope", "Peak Flow", "Base Flow", "d/D"]
        all_files_data.each do |fd|
          if fd[:sections]['Pipes']
            fd[:sections]['Pipes'].each do |id, v|
              csv << [fd[:relative_path], id, 'Pipe', v[2] || 0, v[3] || 0, v[9] || 0, v[10] || 0, v[1] || 0, v[6] || 0, v[0] || 0, v[10] || 0]
            end
          end
          if fd[:sections]['Force Mains']
            fd[:sections]['Force Mains'].each do |id, v|
              csv << [fd[:relative_path], id, 'Force Main', v[0] || 0, v[1] || 0, v[2] || 0, 1.0, 0, 0, 0, 1.0]
            end
          end
          if fd[:sections]['Pumps']
            fd[:sections]['Pumps'].each do |id, v|
              csv << [fd[:relative_path], id, 'Pump', 0, v[1] || 0, 0, 0, 0, 0, 0, 0]
            end
          end
        end
      end
      ts_log "Exported: #{File.basename(links_file)}"
    rescue => e
      ts_log "ERROR exporting links: #{e.message}"
    end

    # Summary stats
    begin
      stats_file = File.join(output_dir, "summary_statistics_#{timestamp}.csv")
      CSV.open(stats_file, "wb") do |csv|
        csv << ["Section", "Parameter", "Count", "Mean", "Std Dev", "Min", "25th %ile", "Median", "75th %ile", "95th %ile", "Max"]
        aggregate.each do |section, items|
          headers = section_headers[section]
          next unless headers
          headers.each_with_index do |h, ci|
            all_vals = []
            items.each_value { |arrs| arrs.each { |row| all_vals << row[ci] if row && row[ci] } }
            next if all_vals.empty?
            csv << [section, h] + stats_row(all_vals)
          end
        end
      end
      ts_log "Exported: #{File.basename(stats_file)}"
    rescue => e
      ts_log "ERROR exporting summary stats: #{e.message}"
    end
  end

  WSApplication.message_box("Batch RPT Analysis Complete!\nFiles: #{rpt_files.size}\nDir: #{start_dir}", "OK", "Information", false)

rescue => e
  ts_log "FATAL: #{e.class}: #{e.message}"
  puts e.backtrace.first(5).join("\n") if e.backtrace
ensure
  ts_log "Batch RPT analysis finished"
end
