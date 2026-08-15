# ============================================================================
# Create empty InfoWorks networks (+ runs) to match each ICM SWMM network
# ============================================================================
# For every SWMM network, this creates an InfoWorks (Model Network) of the SAME
# NAME in the SAME Model Group, commits it empty, and optionally creates a run
# against it. You then do the actual data load by hand:
#
#     Network > Import > Model > from SWMM network...
#
# Why Exchange and not a UI script: a run needs a COMMITTED network, and
# WSNumbatNetworkObject#open is private in the UI - so an empty new network
# cannot be committed from there. In ICMExchange it is public.
#
# Safe to re-run: it skips any SWMM network that already has an InfoWorks
# network of the same name in the same group. Nothing existing is modified.
#
# Run:  ICM_Make_InfoWorks_Shells_Launch_UI.rb   (from the ICM UI)
#   or: ICMExchange.exe ICM_Make_InfoWorks_Shells_Exchange.rb /ICM
# ============================================================================

# --- CONFIG -----------------------------------------------------------------
ONLY_GROUP  = nil    # only SWMM networks whose path contains this. nil = all
NAME_SUFFIX = ''     # e.g. '_IW' if you do not want identical names
CREATE_RUNS = true   # also create a run per network
COMMIT_EMPTY = true  # commit the empty network (required for a run)
DRY_RUN     = false  # true = report what would happen, create nothing

RUN_PARAMS = {
  'Duration'     => 24,
  'DurationUnit' => 'Hours',
  'TimeStep'     => 30
}
# ----------------------------------------------------------------------------

def log(m)
  puts "[#{Time.now.strftime('%H:%M:%S')}] #{m}"
end

db = WSApplication.open
log "Database GUID: #{begin db.guid rescue '?' end}"
log "DRY RUN - nothing will be created" if DRY_RUN

# ---------------------------------------------------------------------------
# Collect SWMM networks, and note existing InfoWorks names per parent group
# ---------------------------------------------------------------------------
swmm     = []
existing = {}    # "parent_id|name" => true

queue = []
db.root_model_objects.each { |o| queue << o }
until queue.empty?
  o = queue.shift
  if o.type == 'SWMM network'
    keep = ONLY_GROUP ? (begin o.path.to_s.include?(ONLY_GROUP) rescue false end) : true
    swmm << o if keep
  elsif o.type == 'Model Network'
    existing["#{begin o.parent_id rescue '?' end}|#{o.name}"] = true
  end
  begin
    o.children.each { |c| queue << c }
  rescue
  end
end

log "Found #{swmm.length} SWMM network(s)"

created = 0
runs    = 0
skipped = 0
failed  = 0

swmm.each_with_index do |sw, i|
  target_name = "#{sw.name}#{NAME_SUFFIX}"

  parent = begin
    db.model_object_from_type_and_id(sw.parent_type, sw.parent_id)
  rescue => e
    log "[#{i + 1}/#{swmm.length}] #{sw.name}: cannot resolve parent group (#{e.message})"
    nil
  end

  if parent.nil?
    failed += 1
    next
  end

  if existing["#{sw.parent_id}|#{target_name}"]
    log "[#{i + 1}/#{swmm.length}] #{target_name}: already exists - skipped"
    skipped += 1
    next
  end

  log "[#{i + 1}/#{swmm.length}] #{target_name}  (in '#{parent.name}')"

  if DRY_RUN
    created += 1
    next
  end

  hw = begin
    parent.new_model_object('Model Network', target_name)
  rescue => e
    log "    FAILED to create network: #{e.message}"
    failed += 1
    next
  end
  log "    created network id #{hw.id}"
  created += 1
  existing["#{sw.parent_id}|#{target_name}"] = true

  # -- commit the empty network so a run can reference it --------------------
  if COMMIT_EMPTY
    begin
      net = hw.open
      net.commit('Empty InfoWorks network created to receive a SWMM import')
      begin net.close rescue nil end
      log '    committed (empty)'
    rescue => e
      log "    could not commit: #{e.message}"
    end
  end

  # -- run -------------------------------------------------------------------
  next unless CREATE_RUNS

  begin
    params = {}
    RUN_PARAMS.each { |k, v| params[k] = v }

    run = parent.new_run(
      "Run - #{target_name}",   # name
      hw,                       # network
      nil,                      # commit id (nil = latest)
      nil,                      # rainfall events
      nil,                      # scenarios
      params
    )
    log "    created run id #{begin run.id rescue '?' end}"
    runs += 1
  rescue => e
    log "    could not create run: #{e.message}"
  end
end

log ''
log '=' * 60
log "networks created : #{created}"
log "runs created     : #{runs}"
log "skipped (exists) : #{skipped}"
log "failed           : #{failed}"
log '=' * 60
log 'Next: for each new InfoWorks network use'
log '  Network > Import > Model > from SWMM network...'
