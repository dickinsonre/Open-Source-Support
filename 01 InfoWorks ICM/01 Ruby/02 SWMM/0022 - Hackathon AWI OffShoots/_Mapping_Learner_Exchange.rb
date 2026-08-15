# ============================================================================
# SWMM -> InfoWorks MAPPING LEARNER          (ICMExchange mode)
# ============================================================================
# You convert a SWMM network to an InfoWorks network by hand. That converted
# pair is GROUND TRUTH: the same objects, same IDs, expressed in both schemas.
# This script reads such pairs and DERIVES the field mapping from the data
# instead of guessing it.
#
# For every hw_* field it asks: which sw_* field explains this, and how?
#
#   IDENTICAL   hw = sw                        (straight rename)
#   RATIO       hw = sw * k                    (unit conversion, e.g. 0.3048)
#   OFFSET      hw = sw + c
#   LINEAR      hw = m*sw + c
#   CONSTANT    hw is the same value for every object   (an ICM default)
#   TEXT        hw string field equals an sw string field
#   UNEXPLAINED varies, but no single sw field accounts for it
#
# The UNEXPLAINED ones are as valuable as the matches: they are the fields a
# CSV-driven converter cannot fill from SWMM alone, i.e. the parts that need a
# real modelling decision.
#
# READ-ONLY. Opens networks, reads, closes. Never writes, commits or deletes.
#
# Run:  ICMExchange.exe ICM_Mapping_Learner_Exchange.rb /ICM
#   or: ICM_Mapping_Learner_Launch_UI.rb from the ICM UI.
#
# Output: C:\temp\ICM_Mapping_Learner.html  (+ .csv)
# ============================================================================

# --- CONFIG -----------------------------------------------------------------
# Explicit pairs, if auto-matching does not find them. Names must be exact.
#   PAIRS = [ ['SWMM network name', 'InfoWorks network name'], ... ]
PAIRS = [
  # ['Greenville_SWMM', 'Greenville_InfoWorks'],
]

# When PAIRS is empty, pair SWMM and InfoWorks networks whose names normalise
# to the same key (prefixes and timestamps stripped).
AUTO_PAIR = true

# Extra tokens stripped during name normalisation, so a converted network named
# "Greenville_InfoWorks" still matches "SWMM_Import_Greenville_20260814_1851".
STRIP_TOKENS = %w[
  SWMM_Import_ SWMM5_Import_ ICM_ _InfoWorks _IW _HW _SWMM _SW
  InfoWorks_ IW_ HW_ SWMM_ SW_ _converted _Converted _CONV
]

SAMPLE_N   = 400      # objects sampled while searching for a relationship
MIN_N      = 5        # need at least this many matched objects to judge
TOL        = 0.001    # 0.1% relative agreement
ABS_EPS    = 1e-9
CONFIDENT  = 0.98     # fraction of objects that must satisfy a relation
# ----------------------------------------------------------------------------

TABLE_PAIRS = [
  ['sw_node',         'hw_node'],
  ['sw_conduit',      'hw_conduit'],
  ['sw_subcatchment', 'hw_subcatchment']
]

home    = ENV['USERPROFILE'].to_s.gsub('\\', '/')
out_dir = ['C:/temp', File.join(home, 'OneDrive', 'Desktop'), home].find { |d| Dir.exist?(d) } || 'C:/'
HTML_PATH = File.join(out_dir, 'ICM_Mapping_Learner.html')
CSV_PATH  = File.join(out_dir, 'ICM_Mapping_Learner.csv')

def log(m)
  puts "[#{Time.now.strftime('%H:%M:%S')}] #{m}"
end

def esc(s)
  s.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
end

def norm(s)
  t = s.to_s.dup
  STRIP_TOKENS.each { |tok| t = t.gsub(/#{Regexp.escape(tok)}/i, '') }
  t = t.sub(/_?\d{8}_\d{4}\z/, '')
  t.downcase.gsub(/[^a-z0-9]/, '')
end

def median(a)
  return nil if a.nil? || a.empty?
  s = a.sort
  n = s.length
  n.odd? ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2.0
end

def close?(x, y)
  d = (x - y).abs
  return true if d <= ABS_EPS
  denom = y.abs > ABS_EPS ? y.abs : (x.abs > ABS_EPS ? x.abs : 1.0)
  (d / denom) <= TOL
end

# ---------------------------------------------------------------------------
# Collect rows and field values
# ---------------------------------------------------------------------------
def first_row(coll)
  r = nil
  begin
    coll.each { |x| r = x; break }
  rescue
    return nil
  end
  r
end

def field_names_of(sample)
  return [] if sample.nil?
  begin
    return sample.field_names.map(&:to_s)
  rescue
  end
  []
end

# id => row object
def index_rows(net, table)
  idx = {}
  coll = begin net.row_objects(table) rescue nil end
  return [nil, idx] if coll.nil?
  begin
    coll.each do |r|
      k = begin r.id.to_s rescue nil end
      idx[k] = r if k
    end
  rescue
  end
  [coll, idx]
end

# Extract { field => [values...] } aligned to the given id list
def extract(rows_by_id, ids, fields)
  out = {}
  fields.each { |f| out[f] = [] }
  ids.each do |id|
    ro = rows_by_id[id]
    fields.each do |f|
      v = begin ro[f] rescue nil end
      out[f] << v
    end
  end
  out
end

def numeric_series(vals)
  n = 0
  out = vals.map do |v|
    next nil if v.nil?
    f = begin Float(v) rescue nil end
    n += 1 if f
    f
  end
  [out, n]
end

# ---------------------------------------------------------------------------
# Relationship classification for one hw field against all sw fields
# ---------------------------------------------------------------------------
def classify(hw_vals, sw_series)
  # hw_vals: array of Float/nil ; sw_series: { name => array of Float/nil }
  present = hw_vals.compact
  return { kind: 'EMPTY' } if present.empty?

  # constant?
  if present.length >= MIN_N
    m = present[0]
    if present.all? { |v| close?(v, m) }
      return { kind: 'CONSTANT', value: m, score: 1.0, n: present.length }
    end
  end

  best = nil

  sw_series.each do |sname, svals|
    pairs = []
    hw_vals.each_with_index do |h, i|
      s = svals[i]
      pairs << [h, s] if h && s
    end
    next if pairs.length < MIN_N

    n = pairs.length

    # identical
    hits = pairs.count { |h, s| close?(h, s) }
    sc = hits.to_f / n
    best = { kind: 'IDENTICAL', sw: sname, score: sc, n: n } if best.nil? || sc > best[:score]
    next if sc >= CONFIDENT && best[:kind] == 'IDENTICAL' && best[:sw] == sname

    # ratio
    ratios = pairs.select { |_h, s| s.abs > ABS_EPS }.map { |h, s| h / s }
    if ratios.length >= MIN_N
      k = median(ratios)
      if k && k.abs > ABS_EPS
        hits = pairs.count { |h, s| close?(h, k * s) }
        sc = hits.to_f / n
        if best.nil? || sc > best[:score]
          best = { kind: 'RATIO', sw: sname, k: k, score: sc, n: n }
        end
      end
    end

    # offset
    diffs = pairs.map { |h, s| h - s }
    c = median(diffs)
    if c
      hits = pairs.count { |h, s| close?(h, s + c) }
      sc = hits.to_f / n
      if (best.nil? || sc > best[:score]) && c.abs > ABS_EPS
        best = { kind: 'OFFSET', sw: sname, c: c, score: sc, n: n }
      end
    end

    # linear least squares
    sx = 0.0; sy = 0.0; sxx = 0.0; sxy = 0.0
    pairs.each do |h, s|
      sx += s; sy += h; sxx += s * s; sxy += s * h
    end
    den = (n * sxx) - (sx * sx)
    if den.abs > ABS_EPS
      m = ((n * sxy) - (sx * sy)) / den
      b = (sy - (m * sx)) / n
      hits = pairs.count { |h, s| close?(h, (m * s) + b) }
      sc = hits.to_f / n
      if (best.nil? || sc > best[:score]) && m.abs > ABS_EPS
        best = { kind: 'LINEAR', sw: sname, m: m, c: b, score: sc, n: n }
      end
    end
  end

  return { kind: 'UNEXPLAINED', score: 0.0 } if best.nil? || best[:score] < CONFIDENT
  best
end

def classify_text(hw_vals, sw_text)
  present = hw_vals.compact.reject { |v| v.to_s.empty? }
  return nil if present.length < MIN_N

  best = nil
  sw_text.each do |sname, svals|
    pairs = []
    hw_vals.each_with_index do |h, i|
      s = svals[i]
      pairs << [h.to_s, s.to_s] if h && s
    end
    next if pairs.length < MIN_N
    hits = pairs.count { |a, b| a == b }
    sc = hits.to_f / pairs.length
    best = { kind: 'TEXT', sw: sname, score: sc, n: pairs.length } if best.nil? || sc > best[:score]
  end
  return nil if best.nil? || best[:score] < CONFIDENT
  best
end

# ---------------------------------------------------------------------------
# Find pairs
# ---------------------------------------------------------------------------
db = WSApplication.open
log "Database GUID: #{begin db.guid rescue '?' end}"

sw_objs = []
hw_objs = []
queue = []
db.root_model_objects.each { |o| queue << o }
until queue.empty?
  o = queue.shift
  sw_objs << o if o.type == 'SWMM network'
  hw_objs << o if o.type == 'Model Network'
  begin
    o.children.each { |c| queue << c }
  rescue
  end
end
log "Found #{sw_objs.length} SWMM network(s), #{hw_objs.length} InfoWorks network(s)"

pairs = []
if PAIRS.any?
  PAIRS.each do |swn, hwn|
    s = sw_objs.find { |o| o.name == swn }
    h = hw_objs.find { |o| o.name == hwn }
    if s && h
      pairs << [s, h]
    else
      log "  WARNING: explicit pair not found: #{swn} / #{hwn}"
    end
  end
elsif AUTO_PAIR
  hw_by_key = {}
  hw_objs.each { |o| hw_by_key[norm(o.name)] ||= o }
  sw_objs.each do |s|
    h = hw_by_key[norm(s.name)]
    pairs << [s, h] if h
  end
end

log "Matched #{pairs.length} SWMM/InfoWorks pair(s)"
if pairs.empty?
  log ''
  log 'No pairs found. Either convert a SWMM network to InfoWorks first, or list'
  log 'the names explicitly in PAIRS at the top of this script. Names seen:'
  sw_objs.first(15).each { |o| log "  SWMM      : #{o.name}  [key #{norm(o.name)}]" }
  hw_objs.first(15).each { |o| log "  InfoWorks : #{o.name}  [key #{norm(o.name)}]" }
end

# ---------------------------------------------------------------------------
# Learn
# ---------------------------------------------------------------------------
results = []   # { pair:, table:, hw_field:, result: }

pairs.each_with_index do |(swo, hwo), pi|
  log "[#{pi + 1}/#{pairs.length}] #{swo.name}  ->  #{hwo.name}"

  swnet = nil
  hwnet = nil
  begin
    swnet = swo.open
    hwnet = hwo.open

    TABLE_PAIRS.each do |swt, hwt|
      _c1, sw_idx = index_rows(swnet, swt)
      _c2, hw_idx = index_rows(hwnet, hwt)
      next if sw_idx.empty? || hw_idx.empty?

      common = sw_idx.keys & hw_idx.keys
      if common.length < MIN_N
        log "    #{swt}/#{hwt}: only #{common.length} shared ID(s) - skipped"
        next
      end
      ids = common.length > SAMPLE_N ? common.first(SAMPLE_N) : common
      log "    #{swt}/#{hwt}: #{common.length} shared ID(s), sampling #{ids.length}"

      sw_fields = field_names_of(sw_idx[ids[0]])
      hw_fields = field_names_of(hw_idx[ids[0]])
      if sw_fields.empty? || hw_fields.empty?
        log '      (field_names unavailable - skipped)'
        next
      end

      sw_raw = extract(sw_idx, ids, sw_fields)
      hw_raw = extract(hw_idx, ids, hw_fields)

      # split into numeric and text series
      sw_num = {}
      sw_txt = {}
      sw_raw.each do |f, vals|
        nums, cnt = numeric_series(vals)
        if cnt >= (ids.length * 0.5)
          sw_num[f] = nums
        else
          sw_txt[f] = vals
        end
      end

      hw_fields.each do |hf|
        vals = hw_raw[hf]
        nums, cnt = numeric_series(vals)

        res = if cnt >= (ids.length * 0.5)
                classify(nums, sw_num)
              else
                classify_text(vals, sw_txt) || { kind: 'UNEXPLAINED', score: 0.0 }
              end

        results << { pair: "#{swo.name} -> #{hwo.name}", sw_table: swt, hw_table: hwt,
                     hw_field: hf, res: res }
      end
    end
  rescue => e
    log "    ERROR: #{e.class}: #{e.message}"
  ensure
    begin swnet.close if swnet rescue nil end
    begin hwnet.close if hwnet rescue nil end
  end
end

# ---------------------------------------------------------------------------
# Consensus across pairs
# ---------------------------------------------------------------------------
def sig(r)
  case r[:kind]
  when 'IDENTICAL'  then "= #{r[:sw]}"
  when 'RATIO'      then "= #{r[:sw]} * #{r[:k].round(6)}"
  when 'OFFSET'     then "= #{r[:sw]} + #{r[:c].round(6)}"
  when 'LINEAR'     then "= #{r[:m].round(6)} * #{r[:sw]} + #{r[:c].round(6)}"
  when 'TEXT'       then "= #{r[:sw]} (text)"
  when 'CONSTANT'   then "constant #{r[:value]}"
  when 'EMPTY'      then 'empty'
  else                   'unexplained'
  end
end

consensus = {}
results.each do |r|
  key = "#{r[:hw_table]}.#{r[:hw_field]}"
  consensus[key] ||= {}
  s = sig(r[:res])
  consensus[key][s] ||= 0
  consensus[key][s] += 1
end

# ---------------------------------------------------------------------------
# CSV
# ---------------------------------------------------------------------------
begin
  File.open(CSV_PATH, 'w') do |f|
    f.puts 'pair,hw_table,hw_field,kind,sw_field,factor,offset,score,n,expression'
    results.each do |r|
      x = r[:res]
      f.puts([r[:pair], r[:hw_table], r[:hw_field], x[:kind], x[:sw],
              x[:k] || x[:m], x[:c], (x[:score] ? x[:score].round(4) : ''), x[:n], sig(x)]
             .map { |v|
               s = v.to_s
               (s.include?(',') || s.include?('"')) ? '"' + s.gsub('"', '""') + '"' : s
             }.join(','))
    end
  end
  log "CSV written: #{CSV_PATH}"
rescue => e
  log "CSV failed: #{e.message}"
end

# ---------------------------------------------------------------------------
# HTML
# ---------------------------------------------------------------------------
kind_cls = {
  'IDENTICAL' => 'ok', 'RATIO' => 'ok', 'OFFSET' => 'ok', 'LINEAR' => 'mid',
  'TEXT' => 'ok', 'CONSTANT' => 'warn', 'EMPTY' => 'muted', 'UNEXPLAINED' => 'bad'
}

counts = Hash.new(0)
results.each { |r| counts[r[:res][:kind]] += 1 }

rows_html = ''
results.each do |r|
  x = r[:res]
  cls = kind_cls[x[:kind]] || 'muted'
  rows_html += '<tr class="' + cls + '" data-kind="' + x[:kind] + '">'
  rows_html += '<td>' + esc(r[:pair]) + '</td>'
  rows_html += '<td>' + esc(r[:hw_table]) + '</td>'
  rows_html += '<td class="fld">' + esc(r[:hw_field]) + '</td>'
  rows_html += '<td><span class="pill ' + cls + '">' + x[:kind] + '</span></td>'
  rows_html += '<td class="expr">' + esc(sig(x)) + '</td>'
  rows_html += '<td class="num">' + (x[:score] ? (x[:score] * 100).round(1).to_s + '%' : '-') + '</td>'
  rows_html += '<td class="num muted">' + (x[:n] || '-').to_s + '</td>'
  rows_html += "</tr>\n"
end

cons_html = ''
consensus.keys.sort.each do |k|
  variants = consensus[k]
  agreed = variants.length == 1
  cls = agreed ? 'ok' : 'mid'
  cons_html += '<tr class="' + cls + '"><td class="fld">' + esc(k) + '</td><td>'
  cons_html += variants.map { |s, n| esc(s) + ' <span class="muted">(x' + n.to_s + ')</span>' }.join('<br>')
  cons_html += '</td><td>' + (agreed ? 'consistent' : 'DIFFERS ACROSS PAIRS') + '</td></tr>' + "\n"
end

icm_ver = begin WSApplication.version rescue '?' end

html = <<HTMLDOC
<!doctype html>
<html lang="en" data-theme="dark"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>SWMM to InfoWorks Mapping</title>
<style>
:root{--bg:#0f172a;--panel:#1e293b;--line:#334155;--text:#e2e8f0;--muted:#94a3b8;
  --ok:#22c55e;--bad:#f87171;--mid:#fb923c;--warn:#fbbf24}
html[data-theme="light"]{--bg:#f8fafc;--panel:#fff;--line:#e2e8f0;--text:#0f172a;--muted:#64748b;
  --ok:#15803d;--bad:#b91c1c;--mid:#c2410c;--warn:#a16207}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--text);
  font:14px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif}
.wrap{max-width:1400px;margin:0 auto;padding:28px 20px 80px}
h1{font-size:22px;margin:0 0 4px} h2{font-size:16px;margin:30px 0 10px}
.meta{color:var(--muted);font-size:13px;margin-bottom:20px}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(130px,1fr));gap:12px;margin-bottom:22px}
.card{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:14px}
.card .v{font-size:24px;font-weight:600} .card .k{color:var(--muted);font-size:12px;
  text-transform:uppercase;letter-spacing:.06em}
.card.ok .v{color:var(--ok)} .card.bad .v{color:var(--bad)}
.card.mid .v{color:var(--mid)} .card.warn .v{color:var(--warn)}
.controls{display:flex;gap:10px;flex-wrap:wrap;align-items:center;margin-bottom:14px}
button,input,select{background:var(--panel);color:var(--text);border:1px solid var(--line);
  border-radius:8px;padding:8px 12px;font-size:13px;cursor:pointer}
input{cursor:text;min-width:200px}
.tablewrap{overflow-x:auto;border:1px solid var(--line);border-radius:10px;background:var(--panel)}
table{border-collapse:collapse;width:100%;font-size:13px}
th,td{padding:7px 10px;border-bottom:1px solid var(--line);text-align:left;white-space:nowrap}
th{position:sticky;top:0;background:var(--panel);font-size:12px;text-transform:uppercase;
  letter-spacing:.05em;color:var(--muted)}
td.num{text-align:right;font-variant-numeric:tabular-nums}
.muted,td.muted{color:var(--muted)}
td.fld{font-family:ui-monospace,Consolas,monospace}
td.expr{font-family:ui-monospace,Consolas,monospace;white-space:normal}
.pill{padding:2px 8px;border-radius:999px;font-size:11px;font-weight:600;border:1px solid}
.pill.ok{color:var(--ok);border-color:var(--ok)}
.pill.bad{color:var(--bad);border-color:var(--bad)}
.pill.mid{color:var(--mid);border-color:var(--mid)}
.pill.warn{color:var(--warn);border-color:var(--warn)}
.pill.muted{color:var(--muted);border-color:var(--muted)}
tr.ok td:first-child{box-shadow:inset 3px 0 0 var(--ok)}
tr.bad td:first-child{box-shadow:inset 3px 0 0 var(--bad)}
tr.mid td:first-child{box-shadow:inset 3px 0 0 var(--mid)}
tr.warn td:first-child{box-shadow:inset 3px 0 0 var(--warn)}
.note{color:var(--muted);font-size:12px;margin-bottom:10px}
</style></head><body><div class="wrap">

<h1>SWMM &rarr; InfoWorks field mapping, derived from converted pairs</h1>
<div class="meta">#{Time.now.strftime('%Y-%m-%d %H:%M')} &middot; ICM #{icm_ver}
 &middot; #{pairs.length} pair(s) &middot; #{results.length} hw field(s) analysed
 &middot; agreement threshold #{(CONFIDENT * 100).round}% at #{(TOL * 100).round(3)}% tolerance</div>

<div class="cards">
  <div class="card ok"><div class="k">Identical</div><div class="v">#{counts['IDENTICAL']}</div></div>
  <div class="card ok"><div class="k">Ratio</div><div class="v">#{counts['RATIO']}</div></div>
  <div class="card ok"><div class="k">Offset</div><div class="v">#{counts['OFFSET']}</div></div>
  <div class="card mid"><div class="k">Linear</div><div class="v">#{counts['LINEAR']}</div></div>
  <div class="card ok"><div class="k">Text</div><div class="v">#{counts['TEXT']}</div></div>
  <div class="card warn"><div class="k">Constant</div><div class="v">#{counts['CONSTANT']}</div></div>
  <div class="card bad"><div class="k">Unexplained</div><div class="v">#{counts['UNEXPLAINED']}</div></div>
  <div class="card"><div class="k">Empty</div><div class="v">#{counts['EMPTY']}</div></div>
</div>

<div class="note">CONSTANT means the InfoWorks field held one value for every object - an ICM default a converter can simply write.
UNEXPLAINED means the field varies but no single SWMM field accounts for it: derived, or a genuine modelling decision.</div>

<div class="controls">
  <select id="kind">
    <option value="">All kinds</option>
    <option value="IDENTICAL">Identical</option>
    <option value="RATIO">Ratio</option>
    <option value="OFFSET">Offset</option>
    <option value="LINEAR">Linear</option>
    <option value="TEXT">Text</option>
    <option value="CONSTANT">Constant</option>
    <option value="UNEXPLAINED">Unexplained</option>
    <option value="EMPTY">Empty</option>
  </select>
  <input id="q" placeholder="Filter by field name...">
  <button id="theme">Light / dark</button>
  <span class="muted" id="count"></span>
</div>

<div class="tablewrap">
<table id="t"><thead><tr>
<th>Pair</th><th>Table</th><th>InfoWorks field</th><th>Kind</th>
<th>Derived expression</th><th class="num">Score</th><th class="num">n</th>
</tr></thead><tbody>
#{rows_html}
</tbody></table>
</div>

<h2>Consensus across pairs</h2>
<div class="note">A mapping seen identically in every pair is far more trustworthy than one seen once.
Rows marked DIFFERS need a look - the relationship may depend on model settings such as units.</div>
<div class="tablewrap">
<table><thead><tr><th>InfoWorks field</th><th>Derived expression(s)</th><th>Agreement</th></tr></thead>
<tbody>
#{cons_html}
</tbody></table>
</div>

<script>
function rowsOf(){return Array.prototype.slice.call(document.querySelectorAll('#t tbody tr'));}
function apply(){
  var k=document.getElementById('kind').value;
  var q=document.getElementById('q').value.toLowerCase();
  var n=0;
  rowsOf().forEach(function(tr){
    var okK = !k || tr.getAttribute('data-kind')===k;
    var okQ = tr.textContent.toLowerCase().indexOf(q)>=0;
    var vis = okK && okQ;
    tr.style.display = vis?'':'none';
    if(vis) n++;
  });
  document.getElementById('count').textContent = n+' shown';
}
document.getElementById('kind').onchange=apply;
document.getElementById('q').oninput=apply;
document.getElementById('theme').onclick=function(){
  var h=document.documentElement;
  h.setAttribute('data-theme', h.getAttribute('data-theme')==='light'?'dark':'light');
};
apply();
</script>
</div></body></html>
HTMLDOC

begin
  File.open(HTML_PATH, 'w') { |f| f.write(html) }
  log "HTML written: #{HTML_PATH}"
rescue => e
  log "HTML failed: #{e.message}"
end

log ''
log "SUMMARY  pairs=#{pairs.length}  fields=#{results.length}"
counts.keys.sort.each { |k| log "  #{k}: #{counts[k]}" }
log "Open: #{HTML_PATH}"
