# ============================================================================
# SWMM5 Import WITH CLEANUP - EXCHANGE SCRIPT (Version 3 - Refactored & Enhanced)
# ============================================================================
# 
# WHAT THIS SCRIPT DOES:
#   Processes SWMM5 .inp files via ICMExchange, importing them into ICM SWMM Networks.
#   
#   Phases: Import -> Cleanup (sw_label) -> Validation -> Reporting
#
# NEW IN VERSION 3:
#   - Refactored into functional components.
#   - Implemented cleanup of empty visualization labels (sw_label table).
#   - Enhanced validation logic (accurate connectivity checks).
#   - Added performance timing metrics.
#   - Uses Ruby Logger for structured log files.
#
# RUNS AUTOMATICALLY:
#   Launched by the UI script. Reads configuration via ENV['ICM_IMPORT_CONFIG'].
#
# ============================================================================

require 'yaml'
require 'logger'
require 'fileutils'
require 'set'

# ----------------------------------------------------------------------------
# Global State and Helpers
# ----------------------------------------------------------------------------

$script_logger = nil
# One entry per .inp processed, used to build the HTML report
$file_records = []
$aggregate_stats = {
  files_processed: 0,
  files_successful: 0,
  files_failed: 0,
  total_nodes: 0,
  total_links: 0,
  total_subcatchments: 0,
  total_labels_cleaned: 0,
  total_import_time: 0.0,
  failed_files: [],
  # Networks ICM placed somewhere other than the requested Model Group
  wrong_group: 0,
  # Actual parent path -> count, so the summary can report where they landed
  landed: {},
  # Imported but not committed because ICM validation reported errors
  files_invalid: 0,
  invalid_files: [],
  total_warnings: 0,
  # Blank InfoWorks networks created beside each imported SWMM network
  shells_created: 0,
  shells_skipped: 0,
  shells_failed: 0
}

# Dual logging: Console (simple) and File (structured)
def log(message, level = :info)
  # Output to console (ICMExchange stdout) for live streaming
  puts "[#{Time.now.strftime('%H:%M:%S')}] #{message}"
  # Output to log file
  $script_logger.send(level, message) if $script_logger
end

def time_it
  start_time = Time.now
  yield
  Time.now - start_time
end

# ----------------------------------------------------------------------------
# Initialization and Configuration
# ----------------------------------------------------------------------------
def initialize_script
  # Load configuration strictly from the environment variable
  config_file = ENV['ICM_IMPORT_CONFIG']
  unless config_file && File.exist?(config_file)
    puts "ERROR: Configuration file not found via ICM_IMPORT_CONFIG. Run the UI script first."
    exit 1
  end

  begin
    config = YAML.load_file(config_file)
  rescue => e
    puts "ERROR: Failed to parse configuration file: #{e.message}"
    exit 1
  end

  # Setup Logging
  log_dir = File.join(config['base_directory'], "ICM Import Log Files")
  FileUtils.mkdir_p(log_dir)

  log_filename = File.join(log_dir, "SWMM5_Batch_Import_#{Time.now.strftime('%Y%m%d_%H%M%S')}.log")
  
  $script_logger = Logger.new(log_filename)
  $script_logger.formatter = proc do |severity, datetime, progname, msg|
    "#{datetime.strftime('%Y-%m-%d %H:%M:%S')} [#{severity}] #{msg}\n"
  end

  # Open Database
  begin
    db = WSApplication.open
  rescue => e
    log "Error opening database: #{e.message}", :error
    exit 1
  end

  log "="*70
  log "SWMM5 Import to ICM (V3) - Exchange Script Initialized"
  log "="*70
  log "Database GUID: #{db.guid}"
  log "Files to process: #{config['file_configs'].length}"

  { config: config, db: db, log_dir: log_dir, log_filename: log_filename }
end

# ----------------------------------------------------------------------------
# Object-bearing sections of a SWMM5 .inp, counted for the report so you can
# see what each source file actually contained.
# ----------------------------------------------------------------------------
INP_SECTIONS = %w[
  RAINGAGES SUBCATCHMENTS SUBAREAS INFILTRATION
  AQUIFERS GROUNDWATER SNOWPACKS
  LID_CONTROLS LID_USAGE
  JUNCTIONS OUTFALLS DIVIDERS STORAGE
  CONDUITS PUMPS ORIFICES WEIRS OUTLETS
  XSECTIONS TRANSECTS LOSSES CONTROLS
  POLLUTANTS LANDUSES COVERAGES LOADINGS BUILDUP WASHOFF TREATMENT
  INFLOWS DWF RDII HYDROGRAPHS
  CURVES TIMESERIES PATTERNS
  COORDINATES VERTICES POLYGONS TAGS
]

def swmm_inp_sections(path)
  counts = {}
  cur = nil
  begin
    File.foreach(path) do |raw|
      line = raw.to_s.scrub('').split(';').first.to_s.strip
      next if line.empty?
      if line.start_with?('[')
        name = line.gsub(/[\[\]]/, '').strip.upcase
        cur = INP_SECTIONS.include?(name) ? name : nil
        next
      end
      next unless cur
      counts[cur] = (counts[cur] || 0) + 1
    end
  rescue => e
    return {}
  end
  counts
end

# ----------------------------------------------------------------------------
# Property statistics (n / min / mean / max / total)
#
# Generalises the pattern in "0008 - Database Field Tools / hw_UI_Script Stats
# for ICM Network Tables.rb" (totals of length/area/volume per table): here
# EVERY numeric field of every populated sw_* table is accumulated, and the
# same is done for the known numeric columns of each .inp section, so the two
# sides can be compared per file (e.g. total conduit length in the .inp vs
# total sw_conduit.length in ICM).
# ----------------------------------------------------------------------------

# .inp numeric columns per section (0-based, object name = column 0)
INP_PROP_COLS = {
  'JUNCTIONS'     => { 'invert' => 1, 'max_depth' => 2, 'init_depth' => 3,
                       'sur_depth' => 4, 'ponded_area' => 5 },
  'OUTFALLS'      => { 'invert' => 1 },
  'STORAGE'       => { 'invert' => 1, 'max_depth' => 2, 'init_depth' => 3 },
  'CONDUITS'      => { 'length' => 3, 'roughness' => 4, 'in_offset' => 5,
                       'out_offset' => 6, 'init_flow' => 7, 'max_flow' => 8 },
  'PUMPS'         => { 'startup_depth' => 5, 'shutoff_depth' => 6 },
  'ORIFICES'      => { 'offset' => 4, 'discharge_coeff' => 5 },
  'WEIRS'         => { 'crest_height' => 4, 'discharge_coeff' => 5 },
  'SUBCATCHMENTS' => { 'area' => 3, 'percent_imperv' => 4, 'width' => 5,
                       'slope' => 6 },
  'XSECTIONS'     => { 'geom1' => 2, 'geom2' => 3, 'geom3' => 4, 'geom4' => 5,
                       'barrels' => 6 }
}

NUMERIC_RE = /\A[-+]?(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?\z/

def acc_stat(bucket, key, num)
  a = bucket[key] ||= { n: 0, min: num, max: num, sum: 0.0 }
  a[:n]   += 1
  a[:sum] += num
  a[:min]  = num if num < a[:min]
  a[:max]  = num if num > a[:max]
end

# { "SECTION.property" => {n:, min:, max:, sum:} } from the source .inp.
# Non-numeric tokens (e.g. a transect name in an IRREGULAR Geom1) are skipped.
def swmm_inp_prop_stats(path)
  out = {}
  cur = nil
  begin
    File.foreach(path) do |raw|
      line = raw.to_s.scrub('').split(';').first.to_s.strip
      next if line.empty?
      if line.start_with?('[')
        name = line.gsub(/[\[\]]/, '').strip.upcase
        cur = INP_PROP_COLS.key?(name) ? name : nil
        next
      end
      next unless cur
      tok = line.split(/\s+/)
      next if tok.length < 2
      INP_PROP_COLS[cur].each do |prop, i|
        s = tok[i].to_s
        next unless s =~ NUMERIC_RE
        acc_stat(out, "#{cur}.#{prop}", s.to_f)
      end
    end
  rescue
    return {}
  end
  out
end

# { "sw_table" => { "field" => {n:, min:, max:, sum:} } } for every numeric
# field of every populated sw_* table. Flag and user fields are noise here.
def sw_table_field_stats(net)
  stats = {}
  begin
    net.table_names.each do |t|
      tn = t.to_s
      next unless tn.start_with?('sw_')
      rows = begin net.row_objects(tn) rescue nil end
      next if rows.nil? || rows.length == 0

      sample = nil
      begin
        rows.each { |r| sample = r; break }
      rescue
      end
      next if sample.nil?

      fields = begin sample.field_names.map(&:to_s) rescue [] end
      fields = fields.reject { |f| f.end_with?('_flag') || f.start_with?('user_') || f == 'notes' }
      next if fields.empty?

      acc = {}
      rows.each do |r|
        fields.each do |f|
          v = begin r[f] rescue nil end
          next unless v.is_a?(Numeric)
          acc_stat(acc, f, v.to_f)
        end
      end
      stats[tn] = acc unless acc.empty?
    end
  rescue
  end
  stats
end

# Row counts for every populated sw_* table in the imported network.
def sw_table_counts(net)
  out = {}
  begin
    net.table_names.each do |t|
      tn = t.to_s
      next unless tn.start_with?('sw_')
      n = begin net.row_objects(tn).length rescue nil end
      out[tn] = n if n && n > 0
    end
  rescue
  end
  out
end

# ----------------------------------------------------------------------------
# Find or create a root-level Model Group to hold the imported networks.
# Networks cannot live directly at the database root, so all imports go here.
# ----------------------------------------------------------------------------
def find_or_create_model_group(db, group_name)
  db.root_model_objects.each do |o|
    return o if o.type == 'Model Group' && o.name == group_name
  end
  db.new_model_object('Model Group', group_name)
end

# ----------------------------------------------------------------------------
# Create an empty InfoWorks (Model Network) alongside an imported SWMM network,
# with the SAME NAME in the SAME parent group. That name match is what makes
# Network > Import > Model > from SWMM network pre-select the right pair.
#
# Returns [model_object, nil] on success, or [nil, reason] when skipped.
# ----------------------------------------------------------------------------
def create_infoworks_shell(db, swmm_obj, suffix = '')
  parent = begin
    db.model_object_from_type_and_id(swmm_obj.parent_type, swmm_obj.parent_id)
  rescue => e
    return [nil, "cannot resolve parent group (#{e.message})"]
  end
  return [nil, 'no parent group'] if parent.nil?

  # A distinct suffix (default '_IW') keeps the shell clear of the SWMM name -
  # and of the ghosts deleted networks leave on it.
  name = "#{swmm_obj.name}#{suffix}"

  # Only an existing Model Network of this name is a reason to skip. The import
  # deliberately creates a SWMM network, SWMM run, Inflow, Label List, Selection
  # List and IWSW Climatology all sharing this name - ICM allows that, and
  # treating any of them as a clash skips every shell.
  exists = false
  begin
    parent.children.each do |c|
      exists = true if c.type == 'Model Network' && c.name == name
    end
  rescue
    # if children cannot be listed, fall through and let creation decide
  end
  return [nil, "a Model Network named '#{name}' already exists in #{parent.name}"] if exists

  hw = begin
    parent.new_model_object('Model Network', name)
  rescue => e
    # Probe 8 (16 Aug 2026): network names are unique DATABASE-WIDE per type,
    # and DELETED Model Networks still hold their names invisibly. When the
    # exact name is refused, ask ICM's own generator for the nearest free one
    # (db.new_network_name(type, base, 1, true) -> e.g. "exam1_1") so the shell
    # still gets created - with a loud note, because a renamed shell will NOT
    # be pre-paired by name in the manual conversion dialog.
    alt = begin
      db.new_network_name('Model Network', name, 1, true)
    rescue
      nil
    end

    if alt && !alt.to_s.strip.empty? && alt != name
      begin
        h2 = parent.new_model_object('Model Network', alt)
        log "  NOTE: '#{name}' is held (deleted networks keep their names); " \
            "shell created as '#{alt}' instead. It will NOT auto-pair in the " \
            "SWMM->InfoWorks conversion dialog.", :warn
        h2
      rescue => e2
        return [nil, "ICM refused '#{name}' and fallback '#{alt}': #{e2.message}"]
      end
    else
      return [nil, "ICM refused to create '#{name}': #{e.message}"]
    end
  end

  # Commit it empty so it is a valid version-controlled object and can carry a
  # run. Non-fatal - an uncommitted shell still works for the conversion.
  begin
    n = hw.open
    n.commit('Empty InfoWorks network created to receive a SWMM import')
    begin
      n.close
    rescue
    end
  rescue => e
    # keep the shell even if the empty commit is refused
  end

  [hw, nil]
end

# ----------------------------------------------------------------------------
# Phase 1: Import File
# ----------------------------------------------------------------------------
def import_file(parent_group, file_path, network_name, log_dir)
  log "PHASE 1: Importing SWMM5 data"

  # A SWMM5 .inp is imported at the Model Group level with
  # import_all_sw_model_objects: it parses the file and CREATES the SWMM network
  # (plus any related objects) inside the group. You do NOT pre-create an empty
  # network and import into it - WSOpenNetwork has no #import_ex method.
  import_log_path = File.join(log_dir, "#{File.basename(file_path, '.inp')}_ImportLog_#{Time.now.strftime('%Y%m%d_%H%M%S')}.txt")

  imported_objects = nil
  import_time = time_it do
    imported_objects = parent_group.import_all_sw_model_objects(
        file_path.gsub('/', '\\'),        # SWMM5 .inp (Windows path)
        'inp',                            # format for SWMM5 INP files
        '',                               # scenario name (unused for INP)
        import_log_path.gsub('/', '\\')
    )
  end

  $aggregate_stats[:total_import_time] += import_time
  log "  Import duration: #{sprintf('%.2f', import_time)}s"

  # Handle failure - nothing imported
  if imported_objects.nil? || imported_objects.empty?
    log "  Import process reported failure. Check log: #{import_log_path}", :error
    if File.exist?(import_log_path)
        log "  --- Import Log Contents (First 100 lines) ---", :warn
        File.foreach(import_log_path).with_index do |line, i|
            log "    > #{line.strip}", :warn
            break if i >= 100
        end
        log "  ---------------------------------------------", :warn
    end
    raise "Import failed"
  end

  # Locate the SWMM network the import created (there should be exactly one).
  network = nil
  imported_objects.each { |o| network = o if o.type == 'SWMM network' }
  raise "Import produced no SWMM network object" if network.nil?

  log "  Imported #{imported_objects.length} object(s); network '#{network.name}' (ID: #{network.id})"

  # Where did it ACTUALLY land? import_all_sw_model_objects is called on a Model
  # Group, but ICM does not necessarily place the network inside that group -
  # observed landing in the last group used instead. Report the truth rather
  # than assuming the receiver was honoured.
  begin
    actual_parent_id = network.parent_id
    log "  Actual location: #{network.path}"

    # Record the containing group (the path minus the network itself) so the
    # final summary can state plainly where the networks ended up.
    holder = network.path.to_s.split('>')[0..-2].join('>')
    holder = '(root)' if holder.empty?
    $aggregate_stats[:landed][holder] = ($aggregate_stats[:landed][holder] || 0) + 1

    if actual_parent_id != parent_group.id
      log "  NOTE: ICM placed this network in parent id #{actual_parent_id}, " \
          "not the requested group '#{parent_group.name}' (id #{parent_group.id}).", :warn
      $aggregate_stats[:wrong_group] += 1
    end
  rescue => e
    log "  (could not determine actual location: #{e.message})", :warn
  end

  # The import names the network after the .inp file - rename it to the name the
  # user configured. Non-fatal: keep the imported name if the rename is rejected.
  if network_name && !network_name.empty? && network.name != network_name
    begin
      network.name = network_name
      log "  Renamed network to '#{network_name}'"
    rescue => e
      log "  WARNING: Could not rename network to '#{network_name}': #{e.message}", :warn
    end
  end

  # Surface the importer's SUBSTANTIVE messages - silent data alterations like
  # "Outfalls of type Stage-Flow ... reassigned to type Free" or "[TEMPERATURE]
  # has no matching [TIMESERIES]. Unable to create." - which otherwise sit
  # unread in the per-file import log whenever the import "succeeds". The
  # boilerplate "section is empty ... safely ignore" advisories are dropped.
  import_notes = []
  begin
    if File.exist?(import_log_path)
      File.foreach(import_log_path) do |ln|
        t = ln.to_s.scrub('').strip
        next if t.empty?
        next if t =~ /section is empty/i
        next if t =~ /\AImport (log|from)/i
        import_notes << t
      end
    end
  rescue
  end

  net = network.open

  log "  SUCCESS: Import completed."
  { net: net, network_obj: network, import_notes: import_notes }
end

# ----------------------------------------------------------------------------
# Phase 2: Cleanup (sw_label)
# ----------------------------------------------------------------------------
def cleanup_visualization_labels(net)
  log "PHASE 2: Cleaning up empty visualization labels (sw_label)"
  
  # In SWMM networks, visualization labels are stored in 'sw_label'.
  table_name = 'sw_label'

  # WSOpenNetwork has no #table_exists?, but it does expose #table_names.
  # Use that when available, and still guard the read itself.
  begin
    names = net.table_names
    if names && !names.map(&:to_s).include?(table_name)
      log "  No '#{table_name}' table in this network - nothing to clean."
      return 0
    end
  rescue
    # table_names unavailable - fall through and let the read decide
  end

  labels = begin
    net.row_objects(table_name)
  rescue => e
    log "  Skipping label cleanup (table '#{table_name}' unavailable: #{e.message})", :warn
    return 0
  end

  if labels.nil? || labels.empty?
    return 0
  end
  
  log "  Found #{labels.length} labels. Analyzing for empty content..."
  deleted_count = 0
  
  # Use transaction for safe deletion
  net.transaction_begin
  begin
    labels.each do |label|
      # Check the label text. Field access varies by ICM version, so try the
      # hash-style field first and fall back to the accessor.
      content = begin
        label['text'] || label['label']
      rescue
        begin
          label.label
        rescue
          nil
        end
      end

      if content.nil? || content.to_s.strip.empty?
        label.delete
        deleted_count += 1
      end
    end
    net.transaction_commit
    log "  SUCCESS: Deleted #{deleted_count} empty labels."
  rescue => e
    net.transaction_rollback
    log "  ERROR during label cleanup: #{e.message}. Transaction rolled back.", :error
    return 0
  end
  
  deleted_count
end

# ----------------------------------------------------------------------------
# Phase 3: Validation and Statistics
# ----------------------------------------------------------------------------
def validate_and_report(net)
  log "PHASE 3: Validation and Statistics"
  stats = { nodes: 0, links: 0, subcatchments: 0 }
  warnings = []

  begin
    nodes = net.row_objects('_nodes')
    links = net.row_objects('_links')
    subcatchments = net.row_objects('_subcatchments')

    stats[:nodes] = nodes.length
    stats[:links] = links.length
    stats[:subcatchments] = subcatchments.length

    log "  Statistics: Nodes=#{stats[:nodes]}, Links=#{stats[:links]}, Subs=#{stats[:subcatchments]}"

    # Check 1: Empty network
    if stats[:nodes] == 0 && stats[:links] == 0
      warnings << "Network is empty"
    end

    # Check 2: Disconnected subcatchments
    disconnected_subs = 0
    subcatchments.each do |sub|
      # Check both node_id and subcatchment_id for connection in SWMM networks
      if (sub.node_id.nil? || sub.node_id.empty?) && (sub.subcatchment_id.nil? || sub.subcatchment_id.empty?)
          disconnected_subs += 1
      end
    end
    if disconnected_subs > 0
      warnings << "#{disconnected_subs} subcatchment(s) have no outlet (node or subcatchment)"
    end

    # Check 3: Unconnected nodes (Islanding) - Comprehensive and Robust Check
    connected_nodes = Set.new
    
    # Nodes connected by links
    links.each do |link|
      connected_nodes.add(link.us_node_id) if link.us_node_id && !link.us_node_id.empty?
      connected_nodes.add(link.ds_node_id) if link.ds_node_id && !link.ds_node_id.empty?
    end
    
    # Nodes connected as subcatchment outlets
    subcatchments.each do |sub|
      # We only care if it connects to a node here (sub-to-sub connections don't count for node connectivity)
      connected_nodes.add(sub.node_id) if sub.node_id && !sub.node_id.empty?
    end

    all_node_ids = Set.new
    nodes.each { |node| all_node_ids.add(node.id) }

    # Calculate the difference
    unconnected_nodes = all_node_ids - connected_nodes
    if unconnected_nodes.any?
      examples = unconnected_nodes.to_a.take(5).join(', ')
      warnings << "#{unconnected_nodes.size} node(s) are unconnected (Islands). Examples: #{examples}"
    end

    if warnings.any?
      log "  Validation finished with #{warnings.length} warning(s):", :warn
      warnings.each { |w| log "    * #{w}", :warn }
    else
      log "  Validation passed with no warnings."
    end

  rescue => e
    log "  ERROR during validation/statistics analysis: #{e.message}", :error
  end
  
  stats
end

# ----------------------------------------------------------------------------
# Main Processing Loop
# ----------------------------------------------------------------------------
def main_process_loop(init_data)
  config = init_data[:config]
  db = init_data[:db]
  log_dir = init_data[:log_dir]
  file_configs = config['file_configs']

  log "\n" + "="*70
  log "BATCH PROCESSING STARTING"
  log "="*70

  # Networks must be created inside a Model Group, not at the database root.
  # The UI script sends the group of the network open on the GeoPlan - prefer
  # its id (unambiguous), fall back to the name, then to a created group.
  import_group = nil

  if (gid = config['import_group_id'])
    begin
      import_group = db.model_object_from_type_and_id('Model Group', gid)
      log "Target Model Group by id #{gid}: '#{import_group.name}'" if import_group
    rescue => e
      log "Could not resolve group id #{gid}: #{e.message}", :warn
    end
  end

  if import_group.nil?
    import_group_name = config['import_group_name'] || 'SWMM5 Imports'
    import_group = find_or_create_model_group(db, import_group_name)
    log "Target Model Group by name: '#{import_group.name}'"
  end

  log "Target Model Group: '#{import_group.name}' (ID: #{import_group.id})"

  file_configs.each_with_index do |file_config, index|
    file_basename = file_config['file_basename']
    file_path = file_config['file_path']
    network_name = file_config['network_name']

    log "\n" + "-"*70
    log "[#{index + 1}/#{file_configs.length}] Processing: #{file_basename}"
    log "-"*70

    $aggregate_stats[:files_processed] += 1

    # Per-file record for the HTML report. Filled in as the phases run, and
    # pushed once at the end whatever happens, so failures appear too.
    rec = {
      file: file_basename, network: network_name, status: 'UNKNOWN',
      nodes: 0, links: 0, subs: 0, labels: 0,
      errors: 0, warnings: 0, shell: '', location: '', reason: '',
      seconds: 0.0,
      sections: {},   # SWMM5 .inp section -> row count
      tables: {},     # ICM sw_* table    -> row count
      inp_stats: {},  # "SECTION.prop"    -> {n,min,max,sum}   (.inp values)
      tbl_stats: {}   # "sw_table"        -> {field => {n,min,max,sum}}
    }
    file_started = Time.now
    network_obj = nil
    import_succeeded = false

    begin
      # Input Validation
      raise "File not found" unless File.exist?(file_path)

      # Phase 1: Import
      import_result = import_file(import_group, file_path, network_name, log_dir)
      net = import_result[:net]

      # Two sides of the same story for the report: what the .inp declared,
      # and what ICM ended up holding, table by table.
      rec[:sections]  = swmm_inp_sections(file_path)
      rec[:tables]    = sw_table_counts(net)
      # Property-level statistics for both sides (n/min/mean/max/total)
      rec[:inp_stats] = swmm_inp_prop_stats(file_path)
      rec[:tbl_stats] = sw_table_field_stats(net)

      # Importer messages that changed or dropped data go into the report row.
      notes = import_result[:import_notes] || []
      unless notes.empty?
        notes.first(4).each { |t| log "  importer: #{t}", :warn }
        rec[:reason] = notes.join(' | ')[0, 400]
      end
      network_obj = import_result[:network_obj]
      import_succeeded = true

      # Phase 2: Cleanup (optional - never fail a good import over cosmetics)
      labels_cleaned = 0
      if config['cleanup_empty_label_lists']
        begin
          labels_cleaned = cleanup_visualization_labels(net)
        rescue => e
          log "  WARNING: Label cleanup skipped: #{e.message}", :warn
          labels_cleaned = 0
        end
      end

      # Phase 3: Validation (optional - reporting only, must not fail the import)
      import_stats = {}
      if config['validate_after_import']
        begin
          import_stats = validate_and_report(net)
        rescue => e
          log "  WARNING: Post-import validation skipped: #{e.message}", :warn
          import_stats = {}
        end
      end

      rec[:nodes]  = import_stats[:nodes] || 0
      rec[:links]  = import_stats[:links] || 0
      rec[:subs]   = import_stats[:subcatchments] || 0
      rec[:labels] = labels_cleaned

      # Phase 4: ICM network validation (net.validate) - gates the commit.
      # Returns a collection exposing .error_count / .warning_count / .length,
      # with .message on each entry.
      icm_errors   = 0
      icm_warnings = 0
      validation_ran = false

      if config['run_icm_validation']
        begin
          scenarios = ['Base']
          log "PHASE 4: ICM validation (scenario: #{scenarios.join(', ')})"
          validations = net.validate(scenarios)

          icm_errors   = validations.error_count
          icm_warnings = validations.warning_count
          validation_ran = true

          log "  Validation: #{icm_errors} error(s), #{icm_warnings} warning(s)"

          # Record the messages so failures are diagnosable after the run.
          if validations.length > 0
            val_report = File.join(log_dir, "#{File.basename(file_path, '.inp')}_Validation.txt")
            File.open(val_report, 'w') do |f|
              f.puts "Validation for #{file_basename} (network: #{network_name})"
              f.puts "Errors: #{icm_errors}  Warnings: #{icm_warnings}"
              f.puts "-" * 60
              validations.each { |v| f.puts v.message }
            end
            log "  Validation messages written to: #{File.basename(val_report)}"

            validations.each_with_index do |v, i|
              log "    #{v.message}", (icm_errors > 0 ? :warn : :info)
              break if i >= 9   # keep the main log readable
            end
          end
        rescue => e
          log "  WARNING: ICM validation could not run: #{e.message}", :warn
          validation_ran = false
        end
      end

      rec[:errors]   = icm_errors
      rec[:warnings] = icm_warnings

      # Finalize: Commit - only if validation did not report errors.
      if validation_ran && icm_errors > 0
        $aggregate_stats[:files_invalid] += 1
        $aggregate_stats[:invalid_files] << {
          file: file_basename, network: network_name, errors: icm_errors, warnings: icm_warnings
        }

        if config['commit_even_if_invalid']
          # WSOpenNetwork#commit_bypassing_validation exists precisely for this:
          # keep the data in version control even though ICM flags errors.
          begin
            net.commit_bypassing_validation(
              "Imported SWMM5: #{file_basename}. COMMITTED WITH #{icm_errors} VALIDATION ERROR(S)")
            log "COMMITTED DESPITE #{icm_errors} validation error(s): #{file_basename}", :warn
            rec[:status] = 'COMMITTED (invalid)'
            $aggregate_stats[:total_nodes] += import_stats[:nodes] || 0
            $aggregate_stats[:total_links] += import_stats[:links] || 0
            $aggregate_stats[:total_subcatchments] += import_stats[:subcatchments] || 0
            $aggregate_stats[:total_labels_cleaned] += labels_cleaned
          rescue => e
            log "  Bypass commit failed: #{e.message}", :error
          end
        else
          log "SKIPPED COMMIT: #{file_basename} - #{icm_errors} validation error(s)", :warn
          rec[:status] = 'NOT COMMITTED'
          # Leave the network in place (uncommitted) so it can be inspected/fixed.
        end
      else
        commit_message = "Imported SWMM5: #{file_basename}."
        commit_message += " (Cleaned #{labels_cleaned} empty labels)" if labels_cleaned > 0
        commit_message += " (#{icm_warnings} validation warning(s))" if icm_warnings > 0

        net.commit(commit_message)
        log "Network committed."

        $aggregate_stats[:files_successful] += 1
        $aggregate_stats[:total_nodes] += import_stats[:nodes] || 0
        $aggregate_stats[:total_links] += import_stats[:links] || 0
        $aggregate_stats[:total_subcatchments] += import_stats[:subcatchments] || 0
        $aggregate_stats[:total_labels_cleaned] += labels_cleaned
        $aggregate_stats[:total_warnings] += icm_warnings

        rec[:status] = 'COMMITTED'
        log "SUCCESS: #{file_basename}"
      end

      # Phase 5: blank InfoWorks shell beside the imported SWMM network, so the
      # manual "Import > Model > from SWMM network" dialog pre-pairs them by
      # name. Non-fatal: a shell failure must never spoil a good import.
      if config['create_infoworks_shells'] && network_obj
        begin
          hw, why = create_infoworks_shell(db, network_obj, config['shell_name_suffix'].to_s)
          if hw
            log "  InfoWorks shell created: '#{hw.name}' (id #{hw.id})"
            rec[:shell] = hw.name.to_s
            $aggregate_stats[:shells_created] += 1
          else
            log "  InfoWorks shell skipped: #{why}"
            $aggregate_stats[:shells_skipped] += 1
          end
        rescue => e
          log "  InfoWorks shell failed: #{e.message}", :warn
          $aggregate_stats[:shells_failed] += 1
        end
      end

      # Release the network handle. Also gives the database a clean close for
      # every import, rather than leaving handles open until the process exits.
      begin
        net.close
      rescue => e
        log "  (Could not close network handle: #{e.message})", :warn
      end

    rescue => e
      # Error Handling
      log "FAILURE: Failed to process #{file_basename}. Reason: #{e.message}", :error
      $script_logger.error("Backtrace:\n#{e.backtrace.join("\n")}") if $script_logger
      
      rec[:status] = 'FAILED'
      rec[:reason] = e.message.to_s
      $aggregate_stats[:files_failed] += 1
      $aggregate_stats[:failed_files] << { file: file_basename, reason: e.message }

      # Only discard the network if the IMPORT itself failed. Once Phase 1 has
      # succeeded the data is good, and a later (optional) phase blowing up must
      # never delete a network the user just successfully imported.
      if network_obj && !import_succeeded
        begin
          # WSDatabase has no #find_model_object. Walk the database tree to confirm
          # the partially-created network still exists before attempting to delete
          # it (by name, as the ID may be unreliable if creation failed partially).
          exists = false
          queue = []
          db.root_model_objects.each { |o| queue << o }
          until queue.empty?
            obj = queue.shift
            if obj.type == 'SWMM network' && obj.name == network_name
              exists = true
              break
            end
            obj.children.each { |child| queue << child }
          end

          if exists
            log "Attempting to delete partially processed network '#{network_name}'..."
            network_obj.delete
            log "Successfully deleted network object."
          end
        rescue => cleanup_error
          log "Could not delete network object during cleanup: #{cleanup_error.message}", :error
        end
      end
    end

    # One row per file in the HTML report, successes and failures alike.
    rec[:seconds] = (Time.now - file_started).round(2)
    $file_records << rec
  end
end

# ----------------------------------------------------------------------------
# HTML report - one row per .inp, written next to the log files
# ----------------------------------------------------------------------------
def html_escape(s)
  s.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
end

def generate_html_report(log_dir, duration)
  path = File.join(log_dir, "SWMM5_Import_Report_#{Time.now.strftime('%Y%m%d_%H%M%S')}.html")

  cls_for = lambda do |st|
    case st
    when 'COMMITTED'           then 'ok'
    when 'COMMITTED (invalid)' then 'mid'
    when 'NOT COMMITTED'       then 'mid'
    when 'FAILED'              then 'bad'
    else 'warn'
    end
  end

  rows = ''
  $file_records.each do |r|
    c = cls_for.call(r[:status])
    rows += '<tr class="' + c + '">'
    rows += '<td class="name">' + html_escape(r[:file]) + '</td>'
    rows += '<td class="name">' + html_escape(r[:network]) + '</td>'
    rows += '<td><span class="pill ' + c + '">' + html_escape(r[:status]) + '</span></td>'
    rows += '<td class="num">' + r[:nodes].to_s + '</td>'
    rows += '<td class="num">' + r[:links].to_s + '</td>'
    rows += '<td class="num">' + r[:subs].to_s + '</td>'
    rows += '<td class="num' + (r[:errors].to_i > 0 ? ' delta' : ' muted') + '">' + r[:errors].to_s + '</td>'
    rows += '<td class="num muted">' + r[:warnings].to_s + '</td>'
    rows += '<td class="num muted">' + r[:labels].to_s + '</td>'
    rows += '<td class="muted">' + html_escape(r[:shell]) + '</td>'
    rows += '<td class="num muted">' + r[:seconds].to_s + '</td>'
    rows += '<td class="notes">' + html_escape(r[:reason]) + '</td>'
    rows += "</tr>\n"
  end

  landed = $aggregate_stats[:landed].map { |p, n| "#{html_escape(p)} (#{n})" }.join('<br>')
  landed = '<span class="muted">n/a</span>' if landed.empty?

  # --- matrix builder: rows = files, columns = whatever keys were seen -------
  # Footer carries MIN / MEAN / MAX / TOTAL per column. Min, mean and max are
  # computed over the files that actually CONTAIN the section or table - a file
  # without [PUMPS] says nothing about pump counts, so it is excluded rather
  # than dragged in as a zero.
  build_matrix = lambda do |key, label_strip|
    colvals = {}
    $file_records.each do |r|
      (r[key] || {}).each { |k, v| (colvals[k] ||= []) << v.to_i }
    end
    return ['', 0] if colvals.empty?

    totals = {}
    colvals.each { |k, a| totals[k] = a.inject(0) { |s, v| s + v } }
    ordered = colvals.keys.sort_by { |k| [-totals[k], k] }

    head = '<tr><th>File</th>'
    ordered.each { |k| head += '<th class="num">' + html_escape(k.to_s.sub(label_strip, '')) + '</th>' }
    head += '<th class="num">total</th></tr>'

    body = ''
    $file_records.each do |r|
      vals = r[key] || {}
      next if vals.empty?
      rowtot = vals.values.inject(0) { |a, v| a + v.to_i }
      body += '<tr><td class="name">' + html_escape(r[:file]) + '</td>'
      ordered.each do |k|
        v = vals[k]
        body += v ? '<td class="num">' + v.to_s + '</td>' : '<td class="num zero">.</td>'
      end
      body += '<td class="num tot">' + rowtot.to_s + '</td></tr>' + "\n"
    end

    stat_row = lambda do |label, cls|
      row = '<tr class="' + cls + '"><td class="name">' + label + '</td>'
      ordered.each do |k|
        a = colvals[k]
        v = case label
            when 'MIN'   then a.min
            when 'MAX'   then a.max
            when 'MEAN'  then (totals[k].to_f / a.length).round(1)
            when 'TOTAL' then totals[k]
            end
        row += '<td class="num">' + v.to_s + '</td>'
      end
      row += label == 'TOTAL' ?
        '<td class="num tot">' + totals.values.inject(0) { |s, v| s + v }.to_s + '</td>' :
        '<td class="num zero"></td>'
      row + '</tr>' + "\n"
    end

    foot = stat_row.call('MIN', 'stats') + stat_row.call('MEAN', 'stats') +
           stat_row.call('MAX', 'stats') + stat_row.call('TOTAL', 'totals')

    ['<table><thead>' + head + '</thead><tbody>' + body + foot + '</tbody></table>', ordered.length]
  end

  inp_matrix, inp_cols = build_matrix.call(:sections, '')
  icm_matrix, icm_cols = build_matrix.call(:tables, 'sw_')
  inp_matrix = '<div class="muted">no data</div>' if inp_matrix.empty?
  icm_matrix = '<div class="muted">no data</div>' if icm_matrix.empty?

  # --- per-file property statistics (n / min / mean / max / total) -----------
  fmt = lambda do |v|
    return '-' if v.nil?
    r = v.round(4)
    r == r.to_i ? r.to_i.to_s : r.to_s
  end

  stat_table = lambda do |title, pairs|
    # pairs: [[label, {n:,min:,max:,sum:}], ...]
    return '' if pairs.empty?
    h = '<div class="stath">' + html_escape(title) + '</div>'
    h += '<table><thead><tr><th>property</th><th class="num">n</th>' \
         '<th class="num">min</th><th class="num">mean</th>' \
         '<th class="num">max</th><th class="num">total</th></tr></thead><tbody>'
    pairs.each do |label, a|
      mean = a[:n] > 0 ? a[:sum] / a[:n] : nil
      h += '<tr><td class="fldname">' + html_escape(label) + '</td>'
      h += '<td class="num muted">' + a[:n].to_s + '</td>'
      h += '<td class="num">' + fmt.call(a[:min]) + '</td>'
      h += '<td class="num">' + fmt.call(mean) + '</td>'
      h += '<td class="num">' + fmt.call(a[:max]) + '</td>'
      h += '<td class="num tot">' + fmt.call(a[:sum]) + '</td></tr>'
    end
    h + '</tbody></table>'
  end

  prop_blocks = ''
  $file_records.each do |r|
    next if r[:inp_stats].empty? && r[:tbl_stats].empty?

    inner = ''
    unless r[:inp_stats].empty?
      inner += stat_table.call('SWMM5 .inp properties',
                               r[:inp_stats].sort_by { |k, _| k })
    end
    r[:tbl_stats].sort_by { |t, _| t }.each do |tbl, fields|
      inner += stat_table.call("ICM #{tbl} (#{fields.length} numeric fields)",
                               fields.sort_by { |k, _| k })
    end

    prop_blocks += '<details class="pf"><summary>' + html_escape(r[:file]) +
                   ' <span class="muted">- ' + r[:inp_stats].length.to_s +
                   ' .inp properties, ' + r[:tbl_stats].length.to_s +
                   ' sw table(s)</span></summary><div class="pfbody">' +
                   inner + '</div></details>' + "\n"
  end
  prop_blocks = '<div class="muted">no data</div>' if prop_blocks.empty?

  html = <<HTMLDOC
<!doctype html>
<html lang="en" data-theme="dark"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>SWMM5 Import Report</title>
<style>
:root{--bg:#0f172a;--panel:#1e293b;--line:#334155;--text:#e2e8f0;--muted:#94a3b8;
  --ok:#22c55e;--bad:#f87171;--mid:#fb923c;--warn:#fbbf24}
html[data-theme="light"]{--bg:#f8fafc;--panel:#fff;--line:#e2e8f0;--text:#0f172a;--muted:#64748b;
  --ok:#15803d;--bad:#b91c1c;--mid:#c2410c;--warn:#a16207}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--text);
  font:14px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif}
.wrap{max-width:1400px;margin:0 auto;padding:28px 20px 80px}
h1{font-size:22px;margin:0 0 4px} h2{font-size:16px;margin:28px 0 10px}
.meta{color:var(--muted);font-size:13px;margin-bottom:20px}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(130px,1fr));gap:12px;margin-bottom:20px}
.card{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:14px}
.card .v{font-size:24px;font-weight:600}
.card .k{color:var(--muted);font-size:12px;text-transform:uppercase;letter-spacing:.06em}
.card.ok .v{color:var(--ok)} .card.bad .v{color:var(--bad)} .card.mid .v{color:var(--mid)}
.controls{display:flex;gap:10px;flex-wrap:wrap;margin-bottom:14px}
button,input{background:var(--panel);color:var(--text);border:1px solid var(--line);
  border-radius:8px;padding:8px 12px;font-size:13px;cursor:pointer}
input{cursor:text;min-width:220px}
.tablewrap{overflow-x:auto;border:1px solid var(--line);border-radius:10px;background:var(--panel)}
table{border-collapse:collapse;width:100%;font-size:13px}
th,td{padding:8px 10px;border-bottom:1px solid var(--line);text-align:left;white-space:nowrap}
th{position:sticky;top:0;background:var(--panel);font-size:12px;text-transform:uppercase;
  letter-spacing:.05em;color:var(--muted);cursor:pointer}
td.num{text-align:right;font-variant-numeric:tabular-nums}
td.delta{color:var(--bad);font-weight:600}
.muted,td.muted{color:var(--muted)}
td.name{white-space:normal;min-width:200px}
td.notes{white-space:normal;color:var(--muted);min-width:200px}
tr.ok td:first-child{box-shadow:inset 3px 0 0 var(--ok)}
tr.bad td:first-child{box-shadow:inset 3px 0 0 var(--bad)}
tr.mid td:first-child{box-shadow:inset 3px 0 0 var(--mid)}
.pill{padding:2px 8px;border-radius:999px;font-size:11px;font-weight:600;border:1px solid}
.pill.ok{color:var(--ok);border-color:var(--ok)}
.pill.bad{color:var(--bad);border-color:var(--bad)}
.pill.mid{color:var(--mid);border-color:var(--mid)}
.pill.warn{color:var(--warn);border-color:var(--warn)}
.where{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:12px 14px}
.sub{color:var(--muted);font-size:12px;margin-bottom:8px}
td.zero{color:#475569}
html[data-theme="light"] td.zero{color:#cbd5e1}
td.tot{font-weight:600}
tr.totals td{border-top:2px solid var(--line);font-weight:600;background:rgba(148,163,184,.08)}
tr.stats td{color:var(--muted);font-size:12px;background:rgba(148,163,184,.04)}
tr.stats td.name{font-weight:600}
details.pf{background:var(--panel);border:1px solid var(--line);border-radius:10px;
  margin-bottom:8px;overflow:hidden}
details.pf summary{padding:10px 14px;cursor:pointer;font-weight:600;font-size:13px}
details.pf summary:hover{background:rgba(148,163,184,.08)}
.pfbody{padding:0 14px 12px;overflow-x:auto}
.pfbody table{margin-bottom:12px;font-size:12px}
.stath{font-weight:600;font-size:12px;color:var(--muted);text-transform:uppercase;
  letter-spacing:.05em;margin:10px 0 6px}
td.fldname{font-family:ui-monospace,Consolas,monospace;font-size:12px}
</style></head><body><div class="wrap">

<h1>SWMM5 Import Report</h1>
<div class="meta">#{Time.now.strftime('%Y-%m-%d %H:%M')} &middot;
 #{$file_records.length} file(s) &middot; #{sprintf('%.1f', duration)}s total</div>

<div class="cards">
  <div class="card ok"><div class="k">Committed</div><div class="v">#{$aggregate_stats[:files_successful]}</div></div>
  <div class="card bad"><div class="k">Failed</div><div class="v">#{$aggregate_stats[:files_failed]}</div></div>
  <div class="card mid"><div class="k">Not committed</div><div class="v">#{$aggregate_stats[:files_invalid]}</div></div>
  <div class="card"><div class="k">Nodes</div><div class="v">#{$aggregate_stats[:total_nodes]}</div></div>
  <div class="card"><div class="k">Links</div><div class="v">#{$aggregate_stats[:total_links]}</div></div>
  <div class="card"><div class="k">Subcatchments</div><div class="v">#{$aggregate_stats[:total_subcatchments]}</div></div>
  <div class="card"><div class="k">InfoWorks shells</div><div class="v">#{$aggregate_stats[:shells_created]}</div></div>
  <div class="card mid"><div class="k">Warnings</div><div class="v">#{$aggregate_stats[:total_warnings]}</div></div>
</div>

<div class="controls">
  <button id="only">Show problems only</button>
  <button id="theme">Light / dark</button>
  <input id="q" placeholder="Filter...">
  <span class="muted" id="count"></span>
</div>

<div class="tablewrap">
<table id="t"><thead><tr>
<th>File</th><th>Network</th><th>Status</th>
<th class="num">Nodes</th><th class="num">Links</th><th class="num">Subs</th>
<th class="num">Val err</th><th class="num">Val warn</th><th class="num">Labels</th>
<th>IW shell</th><th class="num">Secs</th><th>Importer notes / reason</th>
</tr></thead><tbody>
#{rows}
</tbody></table>
</div>

<h2>SWMM5 source - objects per section, per file</h2>
<div class="sub">Counted straight from each .inp. #{inp_cols} section(s) present, busiest first. A dot means the section is absent or empty.
MIN / MEAN / MAX are computed over the files that contain the section; TOTAL is across all files.</div>
<div class="tablewrap">#{inp_matrix}</div>

<h2>ICM result - rows per sw_* table, per file</h2>
<div class="sub">Read back from each imported network via table_names. #{icm_cols} table(s) populated.
MIN / MEAN / MAX are computed over the files whose network has the table; TOTAL is across all files.</div>
<div class="tablewrap">#{icm_matrix}</div>

<h2>Property statistics per file</h2>
<div class="sub">n / min / mean / max / total for the numeric columns of each .inp section, and for
every numeric field of every populated sw_* table in the imported network (flag and user fields excluded).
Click a file to expand. Compare e.g. CONDUITS.length (total) against sw_conduit length (total).</div>
#{prop_blocks}

<h2>Where the networks were placed</h2>
<div class="where">#{landed}</div>

<script>
var only=false;
function rowsOf(){return Array.prototype.slice.call(document.querySelectorAll('#t tbody tr'));}
function apply(){
  var q=document.getElementById('q').value.toLowerCase(), n=0;
  rowsOf().forEach(function(tr){
    var bad = tr.className.indexOf('ok') < 0;
    var vis = (!only || bad) && tr.textContent.toLowerCase().indexOf(q)>=0;
    tr.style.display = vis?'':'none'; if(vis)n++;
  });
  document.getElementById('count').textContent=n+' shown';
}
document.getElementById('only').onclick=function(){only=!only;
  this.textContent=only?'Show all':'Show problems only';apply();};
document.getElementById('q').oninput=apply;
document.getElementById('theme').onclick=function(){var h=document.documentElement;
  h.setAttribute('data-theme',h.getAttribute('data-theme')==='light'?'dark':'light');};
document.querySelectorAll('#t thead th').forEach(function(th,i){
  var asc=true;
  th.onclick=function(){
    var tb=document.querySelector('#t tbody'), rs=rowsOf();
    rs.sort(function(a,b){
      var x=a.children[i].textContent.trim(), y=b.children[i].textContent.trim();
      var nx=parseFloat(x), ny=parseFloat(y);
      if(!isNaN(nx)&&!isNaN(ny)) return asc?nx-ny:ny-nx;
      return asc?x.localeCompare(y):y.localeCompare(x);
    });
    asc=!asc; rs.forEach(function(r){tb.appendChild(r);});
  };
});
apply();
</script>
</div></body></html>
HTMLDOC

  begin
    File.open(path, 'w') { |f| f.write(html) }
    log "HTML report: #{path}"
    path
  rescue => e
    log "Could not write HTML report: #{e.message}", :warn
    nil
  end
end

# ----------------------------------------------------------------------------
# Summary Generation
# ----------------------------------------------------------------------------
def generate_summary(init_data, duration)
  log_dir = init_data[:log_dir]

  log "\n" + "="*70
  log "BATCH IMPORT SUMMARY"
  log "="*70
  log "Total duration: #{sprintf('%.2f', duration)}s"
  log "Files processed: #{$aggregate_stats[:files_processed]}"
  log "Successful: #{$aggregate_stats[:files_successful]}"
  log "Failed: #{$aggregate_stats[:files_failed]}"
  log "Imported but NOT committed (validation errors): #{$aggregate_stats[:files_invalid]}"
  if $aggregate_stats[:shells_created] > 0 || $aggregate_stats[:shells_skipped] > 0 ||
     $aggregate_stats[:shells_failed] > 0
    log "Blank InfoWorks shells: #{$aggregate_stats[:shells_created]} created, " \
        "#{$aggregate_stats[:shells_skipped]} skipped, #{$aggregate_stats[:shells_failed]} failed"
  end

  if $aggregate_stats[:files_invalid] > 0
    log "\nNetworks left uncommitted (fix and commit manually):"
    $aggregate_stats[:invalid_files].each do |v|
      log "  * #{v[:network]} - #{v[:errors]} error(s), #{v[:warnings]} warning(s)  [#{v[:file]}]", :warn
    end
  end

  if $aggregate_stats[:files_successful] > 0
    log "\nAggregate Statistics:"
    log "  Nodes: #{$aggregate_stats[:total_nodes]}"
    log "  Links: #{$aggregate_stats[:total_links]}"
    log "  Subcatchments: #{$aggregate_stats[:total_subcatchments]}"
    log "  Empty Labels Cleaned: #{$aggregate_stats[:total_labels_cleaned]}"

    log "\nPerformance Metrics:"
    avg_import = $aggregate_stats[:total_import_time] / $aggregate_stats[:files_successful]
    log "  Total Import Time: #{sprintf('%.2f', $aggregate_stats[:total_import_time])}s (Avg: #{sprintf('%.2f', avg_import)}s)"
  end

  if $aggregate_stats[:failed_files].any?
    log "\nFailed Files:", :warn
    $aggregate_stats[:failed_files].each do |failed|
      log "  * #{failed[:file]}: #{failed[:reason]}", :warn
    end
  end

  # Write summary file for UI script
  html_path = generate_html_report(log_dir, duration)

  summary_file = File.join(log_dir, "batch_summary.txt")
  begin
    File.open(summary_file, 'w') do |f|
        f.puts "BATCH_IMPORT_SUMMARY"
        f.puts "files_processed=#{$aggregate_stats[:files_processed]}"
        f.puts "files_successful=#{$aggregate_stats[:files_successful]}"
        f.puts "files_failed=#{$aggregate_stats[:files_failed]}"
        f.puts "total_nodes=#{$aggregate_stats[:total_nodes]}"
        f.puts "total_links=#{$aggregate_stats[:total_links]}"
        f.puts "total_subcatchments=#{$aggregate_stats[:total_subcatchments]}"
        f.puts "total_labels_cleaned=#{$aggregate_stats[:total_labels_cleaned]}"
        f.puts "files_invalid=#{$aggregate_stats[:files_invalid]}"
        f.puts "total_warnings=#{$aggregate_stats[:total_warnings]}"
        f.puts "wrong_group=#{$aggregate_stats[:wrong_group]}"
        f.puts "shells_created=#{$aggregate_stats[:shells_created]}"
        f.puts "shells_skipped=#{$aggregate_stats[:shells_skipped]}"
        f.puts "shells_failed=#{$aggregate_stats[:shells_failed]}"
        f.puts "html_report=#{html_path}" if html_path
        # Where the networks actually ended up (one line each, name|count)
        $aggregate_stats[:landed].each { |path, n| f.puts "landed_group=#{path}|#{n}" }
        f.puts "total_duration=#{sprintf('%.2f', duration)}"
    end
  rescue => e
    log "ERROR: Failed to write summary file: #{e.message}", :error
  end
end

# ============================================================================
# Script Execution
# ============================================================================
start_time = Time.now
init_data = nil
begin
  init_data = initialize_script
  main_process_loop(init_data)
rescue => e
  log "A critical error occurred during execution: #{e.message}", :fatal
  log e.backtrace.join("\n"), :fatal
ensure
  duration = Time.now - start_time
  generate_summary(init_data, duration) if init_data
  $script_logger.close if $script_logger
end

# Exit with appropriate code
exit($aggregate_stats[:files_failed] > 0 ? 1 : 0)