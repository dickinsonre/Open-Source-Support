# ============================================================================
# Create ICM runs for InfoWorks networks, timed from the SWMM .inp
# ============================================================================
# The shell-builder script created the empty InfoWorks networks but its run
# creation may have failed silently-ish. This script does runs only, and is
# deliberately self-diagnosing:
#
#   1. If the database already has a Run, it dumps that run's readable
#      parameters first - that tells us the REAL key names rather than guesses.
#   2. It reads START_DATE / START_TIME / END_DATE / END_TIME / ROUTING_STEP
#      from the matching SWMM .inp so the ICM run covers the same period.
#   3. It calls new_run with progressively simpler parameter sets and reports
#      exactly which one ICM accepted, and the precise error for the ones it
#      rejected.
#
# new_run signature (from repo example 0007):
#   group.new_run(name, network, commit_id, events, scenarios, params_hash)
#
# Safe to re-run: skips networks that already have a run of the target name.
#
# Run:  ICM_Make_Runs_Launch_UI.rb   from the ICM UI
#   or: ICMExchange.exe ICM_Make_Runs_Exchange.rb /ICM
# ============================================================================

# --- CONFIG -----------------------------------------------------------------
INP_DIRS = [
  'C:/Users/rober/GitHub/1729-SWMM5-Models-2030/Simon_EPA',
  'C:/Users/rober/GitHub/1729-SWMM5-Models-2030/OWA_USER'
]

ONLY_GROUP    = nil                 # nil = all InfoWorks networks
RUN_PREFIX    = 'Run - '
NAME_PREFIXES = ['SWMM_Import_', 'SWMM5_Import_']

DEFAULT_DURATION_H = 24.0           # used when the .inp gives no usable period
DEFAULT_TIMESTEP_S = 30
DRY_RUN            = false
# ----------------------------------------------------------------------------

def log(m)
  puts "[#{Time.now.strftime('%H:%M:%S')}] #{m}"
end

def norm(s)
  t = s.to_s.dup
  NAME_PREFIXES.each { |p| t = t.sub(/\A#{Regexp.escape(p)}/i, '') }
  t = t.sub(/_\d{8}_\d{4}\z/, '')
  t.downcase.gsub(/[^a-z0-9]/, '')
end

# ---------------------------------------------------------------------------
# SWMM [OPTIONS] - simulation period and step
# ---------------------------------------------------------------------------
def inp_timing(path)
  o = {}
  cur = nil
  begin
    File.foreach(path) do |raw|
      line = raw.to_s.scrub('').split(';').first.to_s.strip
      next if line.empty?
      if line.start_with?('[')
        cur = line.gsub(/[\[\]]/, '').strip.upcase
        next
      end
      next unless cur == 'OPTIONS'
      t = line.split(/\s+/)
      next if t.length < 2
      o[t[0].to_s.upcase] = t[1]
    end
  rescue
    return nil
  end

  sd = o['START_DATE']; st = o['START_TIME'] || '00:00:00'
  ed = o['END_DATE'];   et = o['END_TIME']   || '00:00:00'

  hours = nil
  if sd && ed
    begin
      m1, d1, y1 = sd.split('/').map(&:to_i)
      m2, d2, y2 = ed.split('/').map(&:to_i)
      sh = st.split(':').map(&:to_i)
      eh = et.split(':').map(&:to_i)
      t1 = Time.new(y1, m1, d1, sh[0] || 0, sh[1] || 0, sh[2] || 0)
      t2 = Time.new(y2, m2, d2, eh[0] || 0, eh[1] || 0, eh[2] || 0)
      hours = (t2 - t1) / 3600.0
      hours = nil if hours <= 0
    rescue
      hours = nil
    end
  end

  step = nil
  if (rs = o['ROUTING_STEP'])
    if rs.include?(':')
      p = rs.split(':').map(&:to_f)
      step = (p[0] * 3600) + (p[1] * 60) + (p[2] || 0)
    else
      step = rs.to_f
    end
    step = nil if step && step <= 0
  end

  { start_date: sd, start_time: st, end_date: ed, end_time: et,
    hours: hours, step: step }
end

# ---------------------------------------------------------------------------
db = WSApplication.open
log "Database GUID: #{begin db.guid rescue '?' end}"
log 'DRY RUN - nothing will be created' if DRY_RUN

# collect .inp files
inp = {}
INP_DIRS.each do |d|
  next unless Dir.exist?(d)
  Dir.glob(File.join(d, '**', '*.inp'), File::FNM_CASEFOLD).each do |f|
    inp[norm(File.basename(f, '.inp'))] ||= f if File.file?(f)
  end
end
log "Indexed #{inp.size} .inp file(s)"

# walk the tree
hw       = []
existing = {}
sample_run = nil

queue = []
db.root_model_objects.each { |o| queue << o }
until queue.empty?
  o = queue.shift
  case o.type
  when 'Model Network'
    keep = ONLY_GROUP ? (begin o.path.to_s.include?(ONLY_GROUP) rescue false end) : true
    hw << o if keep
  when 'Run'
    existing["#{begin o.parent_id rescue '?' end}|#{o.name}"] = true
    sample_run ||= o
  end
  begin
    o.children.each { |c| queue << c }
  rescue
  end
end
log "Found #{hw.length} InfoWorks network(s), #{existing.size} existing run(s)"

# ---------------------------------------------------------------------------
# Show an existing run's parameters - the authoritative key names
# ---------------------------------------------------------------------------
if sample_run
  log ''
  log "Reference run: '#{sample_run.name}' (id #{sample_run.id})"
  begin
    fn = sample_run.field_names.map(&:to_s).sort
    log "  fields (#{fn.length}): #{fn.join(', ')}"
    fn.each do |f|
      v = begin sample_run[f] rescue nil end
      next if v.nil? || v.to_s.strip.empty?
      log "    #{f} = #{v}"
    end
  rescue => e
    log "  (could not read run fields: #{e.message})"
  end
  log ''
else
  log 'No existing Run found to use as a reference.'
end

# ---------------------------------------------------------------------------
created = 0
skipped = 0
failed  = 0
first_success_shape = nil

hw.each_with_index do |net, i|
  run_name = "#{RUN_PREFIX}#{net.name}"

  parent = begin
    db.model_object_from_type_and_id(net.parent_type, net.parent_id)
  rescue => e
    log "[#{i + 1}/#{hw.length}] #{net.name}: no parent (#{e.message})"
    failed += 1
    next
  end

  if existing["#{net.parent_id}|#{run_name}"]
    skipped += 1
    next
  end

  # timing from the matching .inp
  f = inp[norm(net.name)]
  t = f ? inp_timing(f) : nil
  hours = (t && t[:hours]) || DEFAULT_DURATION_H
  step  = (t && t[:step])  || DEFAULT_TIMESTEP_S
  src   = f ? File.basename(f) : 'no .inp matched - defaults'

  log "[#{i + 1}/#{hw.length}] #{run_name}"
  log "    #{src}: duration #{hours.round(3)} h, timestep #{step.round} s" +
      (t && t[:start_date] ? ", start #{t[:start_date]} #{t[:start_time]}" : '')

  if DRY_RUN
    created += 1
    next
  end

  # Parameter shapes, richest first. ICM rejects unknown keys, so fall back.
  shapes = []
  if t && t[:start_date]
    shapes << ['duration+start', {
      'Duration' => hours, 'DurationUnit' => 'Hours', 'TimeStep' => step,
      'StartDate' => t[:start_date], 'StartTime' => t[:start_time]
    }]
  end
  shapes << ['duration+timestep', {
    'Duration' => hours, 'DurationUnit' => 'Hours', 'TimeStep' => step
  }]
  shapes << ['duration only', { 'Duration' => hours, 'DurationUnit' => 'Hours' }]
  shapes << ['empty params', {}]

  # If one shape already worked, try it first next time.
  if first_success_shape
    idx = shapes.index { |n, _| n == first_success_shape }
    shapes.unshift(shapes.delete_at(idx)) if idx
  end

  ok = false
  shapes.each do |label, params|
    begin
      run = parent.new_run(run_name, net, nil, nil, nil, params)
      log "    created run id #{begin run.id rescue '?' end}  [#{label}]"
      first_success_shape ||= label
      created += 1
      existing["#{net.parent_id}|#{run_name}"] = true
      ok = true
      break
    rescue => e
      log "    [#{label}] rejected: #{e.message}"
    end
  end

  failed += 1 unless ok
end

log ''
log '=' * 60
log "runs created : #{created}"
log "skipped      : #{skipped}"
log "failed       : #{failed}"
log "shape used   : #{first_success_shape || 'none succeeded'}"
log '=' * 60
