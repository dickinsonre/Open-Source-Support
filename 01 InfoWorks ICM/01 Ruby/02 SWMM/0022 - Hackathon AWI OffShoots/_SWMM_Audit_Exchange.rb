# ============================================================================
# ICM SWMM Import Audit  ->  HTML report      (ICMExchange mode)
# ============================================================================
# For every SWMM network in the database this:
#
#   1. COUNTS what ICM holds (_nodes / _links / _subcatchments, plus a
#      per-table breakdown discovered via table_names)
#   2. COUNTS what the source .inp declares (parsed section by section)
#   3. COMPARES FIELD VALUES object by object - invert elevations, conduit
#      lengths, roughness, diameters, subcatchment area/width/slope/imperv -
#      matching on object ID, flagging any relative difference > TOLERANCE
#   4. Detects systematic UNIT MISMATCH (e.g. every length off by 0.3048)
#      by taking the median ICM/.inp ratio per field
#
# READ-ONLY: opens networks, reads, closes. Never edits, commits or deletes.
#
# ICM field names are NOT hard-coded. For each logical quantity a list of
# candidate names is probed against the first row object, and the first one
# that actually resolves is used. The report says which name won, and lists
# every field the table really has, so the mapping can be refined.
#
# Run:  ICMExchange.exe ICM_SWMM_Audit_Exchange.rb /ICM
#   or: ICM_SWMM_Audit_Launch_UI.rb from the ICM UI.
#
# Output: C:\temp\ICM_SWMM_Audit.html  (+ .csv)
# ============================================================================

# --- CONFIG -----------------------------------------------------------------
INP_DIRS = [
  'C:/Users/rober/GitHub/1729-SWMM5-Models-2030/Simon_EPA'
]

ONLY_GROUP    = nil                      # nil = every SWMM network
NAME_PREFIXES = ['SWMM_Import_', 'SWMM5_Import_']

COMPARE_FIELDS = true                    # false = counts only (much faster)
TOLERANCE      = 0.001                   # 0.1% relative, as per the CN/BN tools
ABS_EPSILON    = 1e-6                    # ignore differences below this
MAX_EXAMPLES   = 8                       # worst offenders listed per field
# ----------------------------------------------------------------------------

home    = ENV['USERPROFILE'].to_s.gsub('\\', '/')
out_dir = ['C:/temp', File.join(home, 'OneDrive', 'Desktop'), home].find { |d| Dir.exist?(d) } || 'C:/'
HTML_PATH = File.join(out_dir, 'ICM_SWMM_Audit.html')
CSV_PATH  = File.join(out_dir, 'ICM_SWMM_Audit.csv')

def log(m)
  puts "[#{Time.now.strftime('%H:%M:%S')}] #{m}"
end

def esc(s)
  s.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
end

# ---------------------------------------------------------------------------
# .inp SECTION LAYOUTS
# Column indexes are 0-based, counting the object name as column 0.
# ---------------------------------------------------------------------------
NODE_SECTIONS = %w[JUNCTIONS OUTFALLS STORAGE DIVIDERS]
LINK_SECTIONS = %w[CONDUITS PUMPS ORIFICES WEIRS OUTLETS]
SUB_SECTIONS  = %w[SUBCATCHMENTS]
VALUE_SECTIONS = %w[JUNCTIONS OUTFALLS STORAGE CONDUITS XSECTIONS SUBCATCHMENTS]
ALL_SECTIONS  = (NODE_SECTIONS + LINK_SECTIONS + SUB_SECTIONS + ['XSECTIONS']).uniq

# ---------------------------------------------------------------------------
# ICM field-name candidates per logical quantity (first that resolves wins)
# ---------------------------------------------------------------------------
NODE_FIELD_CANDIDATES = {
  invert:     %w[invert_elevation invert_level base_elevation chamber_floor],
  max_depth:  %w[maximum_depth max_depth depth],
  ponded:     %w[ponded_area flooded_area floodable_area]
}
LINK_FIELD_CANDIDATES = {
  length:     %w[length conduit_length],
  roughness:  %w[Mannings_N mannings_n roughness_N roughness bottom_roughness_N],
  geom1:      %w[height conduit_height diameter geom1]
}
SUB_FIELD_CANDIDATES = {
  area:       %w[area total_area],
  imperv:     %w[imperviousness percent_impervious imperv pct_impervious],
  width:      %w[width],
  slope:      %w[slope percent_slope]
}

# .inp column index for each logical quantity, per section
INP_NODE_COLS = {
  'JUNCTIONS' => { invert: 1, max_depth: 2, ponded: 5 },
  'OUTFALLS'  => { invert: 1 },
  'STORAGE'   => { invert: 1, max_depth: 2 }
}
INP_LINK_COLS = { 'CONDUITS' => { length: 3, roughness: 4 } }
INP_SUB_COLS  = { 'SUBCATCHMENTS' => { area: 3, imperv: 4, width: 5, slope: 6 } }
# XSECTIONS: Link Shape Geom1 Geom2 Geom3 Geom4 Barrels
INP_XSEC_GEOM1 = 2

# ---------------------------------------------------------------------------
# .inp parser - counts plus per-object values
# ---------------------------------------------------------------------------
def parse_inp(path, want_values)
  counts = {}
  ALL_SECTIONS.each { |s| counts[s] = 0 }
  nodes = {}
  links = {}
  subs  = {}
  current = nil

  begin
    File.foreach(path) do |raw|
      line = raw.to_s.scrub('')                 # some .inp files hold non-UTF-8 bytes
      line = line.split(';').first.to_s.strip   # drop comments
      next if line.empty?

      if line.start_with?('[')
        name = line.gsub(/[\[\]]/, '').strip.upcase
        current = ALL_SECTIONS.include?(name) ? name : nil
        next
      end
      next unless current

      counts[current] += 1 unless current == 'XSECTIONS'
      next unless want_values
      next unless VALUE_SECTIONS.include?(current)

      tok = line.split(/\s+/)
      next if tok.empty?
      id = tok[0]

      if (cols = INP_NODE_COLS[current])
        h = nodes[id] ||= {}
        cols.each { |k, i| h[k] = tok[i].to_f if tok[i] }
      elsif (cols = INP_LINK_COLS[current])
        h = links[id] ||= {}
        cols.each { |k, i| h[k] = tok[i].to_f if tok[i] }
      elsif (cols = INP_SUB_COLS[current])
        h = subs[id] ||= {}
        cols.each { |k, i| h[k] = tok[i].to_f if tok[i] }
      elsif current == 'XSECTIONS'
        g = tok[INP_XSEC_GEOM1]
        # IRREGULAR cross-sections put a transect NAME in Geom1, not a number -
        # only record it when it really is numeric, else we invent mismatches.
        num = g ? (begin Float(g) rescue nil end) : nil
        if num
          h = links[id] ||= {}
          h[:geom1] = num
        end
      end
    end
  rescue => e
    return { error: e.message }
  end

  counts[:nodes] = NODE_SECTIONS.inject(0) { |a, s| a + counts[s] }
  counts[:links] = LINK_SECTIONS.inject(0) { |a, s| a + counts[s] }
  counts[:subs]  = SUB_SECTIONS.inject(0)  { |a, s| a + counts[s] }
  counts[:node_vals] = nodes
  counts[:link_vals] = links
  counts[:sub_vals]  = subs
  counts
end

def norm(s)
  t = s.to_s.dup
  NAME_PREFIXES.each { |p| t = t.sub(/\A#{Regexp.escape(p)}/i, '') }
  t = t.sub(/_\d{8}_\d{4}\z/, '')
  t = t.sub(/\.inp\z/i, '')
  t.downcase.gsub(/[^a-z0-9]/, '')
end

# ---------------------------------------------------------------------------
# Field-name resolution: probe candidates against a sample row object
# ---------------------------------------------------------------------------
def resolve_fields(sample, candidates)
  resolved = {}
  return resolved if sample.nil?
  candidates.each do |logical, names|
    names.each do |n|
      begin
        v = sample[n]
        unless v.nil?
          resolved[logical] = n
          break
        end
      rescue
        next
      end
    end
  end
  resolved
end

def field_list(sample)
  return [] if sample.nil?
  begin
    return sample.field_names.map(&:to_s).sort
  rescue
  end
  []
end

# ---------------------------------------------------------------------------
# Compare one ICM table against parsed .inp values
# ---------------------------------------------------------------------------
def compare_table(icm_rows, inp_vals, resolved)
  # returns { logical => {compared:, differing:, ratios:[], examples:[]} }
  out = {}
  resolved.each_key { |k| out[k] = { compared: 0, differing: 0, ratios: [], examples: [] } }
  return out if icm_rows.nil? || inp_vals.empty? || resolved.empty?

  icm_rows.each do |ro|
    id = begin ro.id.to_s rescue next end
    want = inp_vals[id]
    next if want.nil?

    resolved.each do |logical, fname|
      expected = want[logical]
      next if expected.nil?

      actual = begin ro[fname] rescue nil end
      next if actual.nil?
      actual = actual.to_f

      rec = out[logical]
      rec[:compared] += 1

      diff = (actual - expected).abs
      next if diff <= ABS_EPSILON

      denom = expected.abs > ABS_EPSILON ? expected.abs : 1.0
      rel = diff / denom
      rec[:ratios] << (actual / expected) if expected.abs > ABS_EPSILON

      if rel > TOLERANCE
        rec[:differing] += 1
        if rec[:examples].length < MAX_EXAMPLES
          rec[:examples] << { id: id, inp: expected, icm: actual, rel: rel }
        end
      end
    end
  end
  out
end

def median(arr)
  return nil if arr.nil? || arr.empty?
  s = arr.sort
  n = s.length
  n.odd? ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2.0
end

# A consistent non-1 ratio across a field usually means a unit mismatch.
def unit_hint(ratios)
  m = median(ratios)
  return nil if m.nil?
  known = {
    0.3048    => 'ft -> m',
    3.28084   => 'm -> ft',
    0.0929    => 'sq ft -> sq m',
    10.7639   => 'sq m -> sq ft',
    0.4047    => 'acre -> ha',
    2.47105   => 'ha -> acre'
  }
  known.each do |k, label|
    return "#{label} (median ratio #{m.round(5)})" if (m - k).abs / k < 0.01
  end
  return "median ratio #{m.round(5)}" if (m - 1.0).abs > 0.01
  nil
end

# ---------------------------------------------------------------------------
# Collect .inp files
# ---------------------------------------------------------------------------
log 'Scanning for .inp files...'
inp_by_key = {}
inp_total  = 0
INP_DIRS.each do |dir|
  unless Dir.exist?(dir)
    log "  WARNING: folder not found: #{dir}"
    next
  end
  Dir.glob(File.join(dir, '**', '*.inp'), File::FNM_CASEFOLD).each do |f|
    next unless File.file?(f)
    inp_total += 1
    k = norm(File.basename(f, '.inp'))
    inp_by_key[k] ||= f
  end
end
log "  found #{inp_total} .inp file(s), #{inp_by_key.size} unique key(s)"

# ---------------------------------------------------------------------------
# Walk the database
# ---------------------------------------------------------------------------
db = WSApplication.open
log "Database GUID: #{begin db.guid rescue '?' end}"

networks = []
queue = []
db.root_model_objects.each { |o| queue << o }
until queue.empty?
  o = queue.shift
  if o.type == 'SWMM network'
    keep = ONLY_GROUP ? (begin o.path.to_s.include?(ONLY_GROUP) rescue false end) : true
    networks << o if keep
  end
  begin
    o.children.each { |c| queue << c }
  rescue
  end
end
log "Found #{networks.length} SWMM network(s) to audit"

# ---------------------------------------------------------------------------
# Audit
# ---------------------------------------------------------------------------
rows = []
discovered = { 'sw_node' => [], 'sw_conduit' => [], 'sw_subcatchment' => [] }
resolved_report = {}

networks.each_with_index do |mo, i|
  row = {
    name: mo.name, id: mo.id,
    icm_nodes: -1, icm_links: -1, icm_subs: -1,
    inp_file: nil, inp_nodes: nil, inp_links: nil, inp_subs: nil,
    tables: {}, status: 'UNKNOWN', notes: [],
    fields: {}, field_status: nil, unit_flags: []
  }

  log "[#{i + 1}/#{networks.length}] #{mo.name}"

  # ---- source .inp -------------------------------------------------------
  key = norm(mo.name)
  f   = inp_by_key[key]
  parsed = nil
  if f
    row[:inp_file] = f
    parsed = parse_inp(f, COMPARE_FIELDS)
    if parsed[:error]
      row[:notes] << "parse error: #{parsed[:error]}"
      row[:status] = 'PARSE ERROR'
      parsed = nil
    end
  else
    row[:notes] << "no .inp matched (key '#{key}')"
    row[:status] = 'NO SOURCE'
  end

  # ---- ICM side ----------------------------------------------------------
  net = nil
  begin
    net = mo.open
    row[:icm_nodes] = begin net.row_objects('_nodes').length         rescue -1 end
    row[:icm_links] = begin net.row_objects('_links').length         rescue -1 end
    row[:icm_subs]  = begin net.row_objects('_subcatchments').length rescue -1 end

    begin
      net.table_names.each do |t|
        tn = t.to_s
        next unless tn.start_with?('sw_')
        c = begin net.row_objects(tn).length rescue nil end
        row[:tables][tn] = c if c && c > 0
      end
    rescue
    end

    # ---- field-level comparison -----------------------------------------
    if COMPARE_FIELDS && parsed
      specs = [
        ['sw_node',         parsed[:node_vals], NODE_FIELD_CANDIDATES],
        ['sw_conduit',      parsed[:link_vals], LINK_FIELD_CANDIDATES],
        ['sw_subcatchment', parsed[:sub_vals],  SUB_FIELD_CANDIDATES]
      ]

      specs.each do |tbl, vals, cands|
        next if vals.nil? || vals.empty?
        icm_rows = begin net.row_objects(tbl) rescue nil end
        next if icm_rows.nil? || icm_rows.length == 0

        # ICM collections are not full Enumerables (WSModelObjectCollection has
        # no #to_a, for instance), so take the first row by iterating.
        sample = nil
        begin
          icm_rows.each { |r| sample = r; break }
        rescue
          sample = nil
        end
        if discovered[tbl].empty?
          discovered[tbl] = field_list(sample)
        end

        res = resolve_fields(sample, cands)
        resolved_report[tbl] ||= res unless res.empty?

        cmp = compare_table(icm_rows, vals, res)
        cmp.each do |logical, rec|
          next if rec[:compared] == 0
          fq = "#{tbl.sub('sw_', '')}.#{logical}"
          row[:fields][fq] = {
            field: res[logical],
            compared: rec[:compared],
            differing: rec[:differing],
            examples: rec[:examples]
          }
          hint = unit_hint(rec[:ratios])
          row[:unit_flags] << "#{fq}: #{hint}" if hint && rec[:differing] > 0
        end
      end

      tot_cmp  = row[:fields].values.inject(0) { |a, h| a + h[:compared] }
      tot_diff = row[:fields].values.inject(0) { |a, h| a + h[:differing] }
      row[:field_status] = { compared: tot_cmp, differing: tot_diff }
    end
  rescue => e
    row[:notes] << "Could not open network: #{e.message}"
  ensure
    begin
      net.close if net
    rescue
    end
  end

  # ---- count verdict -----------------------------------------------------
  if parsed
    row[:inp_nodes] = parsed[:nodes]
    row[:inp_links] = parsed[:links]
    row[:inp_subs]  = parsed[:subs]

    dn = row[:icm_nodes] - parsed[:nodes]
    dl = row[:icm_links] - parsed[:links]
    ds = row[:icm_subs]  - parsed[:subs]

    counts_ok = (dn == 0 && dl == 0 && ds == 0)
    row[:notes] << "nodes #{dn > 0 ? '+' : ''}#{dn}" unless dn == 0
    row[:notes] << "links #{dl > 0 ? '+' : ''}#{dl}" unless dl == 0
    row[:notes] << "subs #{ds > 0 ? '+' : ''}#{ds}"  unless ds == 0

    fields_ok = row[:field_status].nil? || row[:field_status][:differing] == 0
    row[:notes] << "#{row[:field_status][:differing]} field value(s) differ" if row[:field_status] && row[:field_status][:differing] > 0

    row[:status] = if !counts_ok            then 'COUNT MISMATCH'
                   elsif !fields_ok         then 'VALUE MISMATCH'
                   else                          'MATCH'
                   end
  end

  rows << row
end

# ---------------------------------------------------------------------------
# CSV
# ---------------------------------------------------------------------------
begin
  File.open(CSV_PATH, 'w') do |f|
    f.puts 'network,id,status,icm_nodes,inp_nodes,d_nodes,icm_links,inp_links,d_links,icm_subs,inp_subs,d_subs,fields_compared,fields_differing,inp_file,notes'
    rows.each do |r|
      dn = r[:inp_nodes] ? r[:icm_nodes] - r[:inp_nodes] : ''
      dl = r[:inp_links] ? r[:icm_links] - r[:inp_links] : ''
      ds = r[:inp_subs]  ? r[:icm_subs]  - r[:inp_subs]  : ''
      fc = r[:field_status] ? r[:field_status][:compared]  : ''
      fd = r[:field_status] ? r[:field_status][:differing] : ''
      vals = [r[:name], r[:id], r[:status],
              r[:icm_nodes], r[:inp_nodes], dn,
              r[:icm_links], r[:inp_links], dl,
              r[:icm_subs],  r[:inp_subs],  ds,
              fc, fd, r[:inp_file], r[:notes].join('; ')]
      f.puts(vals.map { |v|
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
n_match  = rows.count { |r| r[:status] == 'MATCH' }
n_count  = rows.count { |r| r[:status] == 'COUNT MISMATCH' }
n_value  = rows.count { |r| r[:status] == 'VALUE MISMATCH' }
n_other  = rows.length - n_match - n_count - n_value

tot_nodes = rows.inject(0) { |a, r| a + (r[:icm_nodes] > 0 ? r[:icm_nodes] : 0) }
tot_links = rows.inject(0) { |a, r| a + (r[:icm_links] > 0 ? r[:icm_links] : 0) }
tot_subs  = rows.inject(0) { |a, r| a + (r[:icm_subs]  > 0 ? r[:icm_subs]  : 0) }
tot_cmp   = rows.inject(0) { |a, r| a + (r[:field_status] ? r[:field_status][:compared]  : 0) }
tot_diff  = rows.inject(0) { |a, r| a + (r[:field_status] ? r[:field_status][:differing] : 0) }

all_tables = {}
rows.each { |r| r[:tables].each_key { |t| all_tables[t] = true } }
table_cols = all_tables.keys.sort

def delta_cell(v)
  return '<td class="num muted">-</td>' if v.nil?
  return '<td class="num">0</td>' if v == 0
  '<td class="num delta">' + (v > 0 ? '+' : '') + v.to_s + '</td>'
end

status_cls = lambda do |s|
  case s
  when 'MATCH'          then 'ok'
  when 'COUNT MISMATCH' then 'bad'
  when 'VALUE MISMATCH' then 'mid'
  else 'warn'
  end
end

body = ''
rows.each_with_index do |r, idx|
  dn = r[:inp_nodes] ? r[:icm_nodes] - r[:inp_nodes] : nil
  dl = r[:inp_links] ? r[:icm_links] - r[:inp_links] : nil
  ds = r[:inp_subs]  ? r[:icm_subs]  - r[:inp_subs]  : nil
  cls = status_cls.call(r[:status])

  fcell = if r[:field_status]
            fs = r[:field_status]
            if fs[:differing] > 0
              '<td class="num delta">' + fs[:differing].to_s + ' / ' + fs[:compared].to_s + '</td>'
            else
              '<td class="num">0 / ' + fs[:compared].to_s + '</td>'
            end
          else
            '<td class="num muted">-</td>'
          end

  body += '<tr class="' + cls + '" data-status="' + r[:status] + '">'
  body += '<td class="name">' + esc(r[:name]) + '<div class="sub">id ' + r[:id].to_s + '</div></td>'
  body += '<td><span class="pill ' + cls + '">' + r[:status] + '</span></td>'
  body += '<td class="num">' + r[:icm_nodes].to_s + '</td><td class="num muted">' + (r[:inp_nodes] || '-').to_s + '</td>' + delta_cell(dn)
  body += '<td class="num">' + r[:icm_links].to_s + '</td><td class="num muted">' + (r[:inp_links] || '-').to_s + '</td>' + delta_cell(dl)
  body += '<td class="num">' + r[:icm_subs].to_s  + '</td><td class="num muted">' + (r[:inp_subs]  || '-').to_s + '</td>' + delta_cell(ds)
  body += fcell
  body += '<td class="notes">' + esc(r[:notes].join('; ')) + '</td>'
  body += "</tr>\n"

  # detail row - per-field breakdown
  unless r[:fields].empty?
    det = ''
    r[:fields].each do |fq, h|
      c = h[:differing] > 0 ? 'delta' : 'muted'
      det += '<div class="frow"><span class="fq">' + esc(fq) + '</span>'
      det += '<span class="fn">[' + esc(h[:field].to_s) + ']</span>'
      det += '<span class="' + c + '">' + h[:differing].to_s + ' differ of ' + h[:compared].to_s + '</span>'
      if h[:differing] > 0 && !h[:examples].empty?
        ex = h[:examples].map { |e|
          esc(e[:id]) + ': inp=' + e[:inp].round(4).to_s + ' icm=' + e[:icm].round(4).to_s +
            ' (' + (e[:rel] * 100).round(2).to_s + '%)'
        }.join(' &middot; ')
        det += '<div class="ex">' + ex + '</div>'
      end
      det += '</div>'
    end
    unless r[:unit_flags].empty?
      det += '<div class="unit">Possible unit mismatch &rarr; ' + esc(r[:unit_flags].join(' | ')) + '</div>'
    end
    body += '<tr class="detail ' + cls + '" data-status="' + r[:status] + '"><td colspan="12">' + det + "</td></tr>\n"
  end
end

detail = ''
unless table_cols.empty?
  detail += '<table><thead><tr><th>Network</th>'
  table_cols.each { |t| detail += '<th class="num">' + esc(t.sub('sw_', '')) + '</th>' }
  detail += "</tr></thead><tbody>\n"
  rows.each do |r|
    detail += '<tr><td class="name">' + esc(r[:name]) + '</td>'
    table_cols.each do |t|
      v = r[:tables][t]
      detail += v ? '<td class="num">' + v.to_s + '</td>' : '<td class="num muted">.</td>'
    end
    detail += "</tr>\n"
  end
  detail += '</tbody></table>'
end

mapping = ''
resolved_report.each do |tbl, res|
  mapping += '<div class="mapblock"><b>' + esc(tbl) + '</b><ul>'
  res.each { |logical, fname| mapping += '<li>' + esc(logical.to_s) + ' &rarr; <code>' + esc(fname) + '</code></li>' }
  mapping += '</ul></div>'
end
discovered.each do |tbl, flds|
  next if flds.empty?
  mapping += '<div class="mapblock"><b>' + esc(tbl) + '</b> fields present (' + flds.length.to_s + ')<div class="flds">' +
             flds.map { |x| '<code>' + esc(x) + '</code>' }.join(' ') + '</div></div>'
end

icm_ver = begin WSApplication.version rescue '?' end

html = <<HTMLDOC
<!doctype html>
<html lang="en" data-theme="dark"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>ICM SWMM Import Audit</title>
<style>
:root{
  --bg:#0f172a; --panel:#1e293b; --line:#334155; --text:#e2e8f0; --muted:#94a3b8;
  --ok:#22c55e; --bad:#f87171; --mid:#fb923c; --warn:#fbbf24;
}
html[data-theme="light"]{
  --bg:#f8fafc; --panel:#ffffff; --line:#e2e8f0; --text:#0f172a; --muted:#64748b;
  --ok:#15803d; --bad:#b91c1c; --mid:#c2410c; --warn:#a16207;
}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--text);
  font:14px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif}
.wrap{max-width:1500px;margin:0 auto;padding:28px 20px 80px}
h1{font-size:22px;margin:0 0 4px}
h2{font-size:16px;margin:30px 0 10px}
.meta{color:var(--muted);font-size:13px;margin-bottom:20px}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(140px,1fr));gap:12px;margin-bottom:22px}
.card{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:14px}
.card .v{font-size:24px;font-weight:600}
.card .k{color:var(--muted);font-size:12px;text-transform:uppercase;letter-spacing:.06em}
.card.ok .v{color:var(--ok)}
.card.bad .v{color:var(--bad)}
.card.mid .v{color:var(--mid)}
.card.warn .v{color:var(--warn)}
.controls{display:flex;gap:10px;flex-wrap:wrap;align-items:center;margin-bottom:14px}
button,input{background:var(--panel);color:var(--text);border:1px solid var(--line);
  border-radius:8px;padding:8px 12px;font-size:13px;cursor:pointer}
input{cursor:text;min-width:220px}
.tablewrap{overflow-x:auto;border:1px solid var(--line);border-radius:10px;background:var(--panel)}
table{border-collapse:collapse;width:100%;font-size:13px}
th,td{padding:8px 10px;border-bottom:1px solid var(--line);text-align:left;white-space:nowrap}
th{position:sticky;top:0;background:var(--panel);cursor:pointer;font-size:12px;
  text-transform:uppercase;letter-spacing:.05em;color:var(--muted)}
td.num{text-align:right;font-variant-numeric:tabular-nums}
td.muted,.muted{color:var(--muted)}
td.delta,.delta{color:var(--bad);font-weight:600}
td.name{white-space:normal;min-width:250px}
td.name .sub{color:var(--muted);font-size:11px}
td.notes{white-space:normal;color:var(--muted);min-width:180px}
tr.bad td:first-child{box-shadow:inset 3px 0 0 var(--bad)}
tr.mid td:first-child{box-shadow:inset 3px 0 0 var(--mid)}
tr.warn td:first-child{box-shadow:inset 3px 0 0 var(--warn)}
tr.ok td:first-child{box-shadow:inset 3px 0 0 var(--ok)}
.pill{padding:2px 8px;border-radius:999px;font-size:11px;font-weight:600;border:1px solid}
.pill.ok{color:var(--ok);border-color:var(--ok)}
.pill.bad{color:var(--bad);border-color:var(--bad)}
.pill.mid{color:var(--mid);border-color:var(--mid)}
.pill.warn{color:var(--warn);border-color:var(--warn)}
tr.detail td{white-space:normal;background:rgba(148,163,184,.06);font-size:12px}
.frow{padding:3px 0;border-bottom:1px dotted var(--line)}
.frow:last-child{border-bottom:none}
.fq{display:inline-block;min-width:190px;font-weight:600}
.fn{display:inline-block;min-width:150px;color:var(--muted)}
.ex{color:var(--muted);margin:2px 0 4px 190px;font-family:ui-monospace,Consolas,monospace;font-size:11px}
.unit{margin-top:6px;color:var(--mid);font-weight:600}
.group{color:var(--muted);font-size:12px;margin-bottom:8px}
.mapblock{background:var(--panel);border:1px solid var(--line);border-radius:10px;
  padding:12px 14px;margin-bottom:10px}
.mapblock ul{margin:6px 0 0;padding-left:18px}
.flds{margin-top:6px;line-height:2}
code{background:rgba(148,163,184,.15);padding:1px 5px;border-radius:4px;font-size:12px}
</style></head><body><div class="wrap">

<h1>ICM SWMM Import Audit</h1>
<div class="meta">#{Time.now.strftime('%Y-%m-%d %H:%M')} &middot; ICM #{icm_ver}
 &middot; #{rows.length} SWMM network(s) &middot; #{inp_total} .inp file(s) scanned
 &middot; tolerance #{(TOLERANCE * 100).round(3)}%</div>

<div class="cards">
  <div class="card ok"><div class="k">Match</div><div class="v">#{n_match}</div></div>
  <div class="card bad"><div class="k">Count mismatch</div><div class="v">#{n_count}</div></div>
  <div class="card mid"><div class="k">Value mismatch</div><div class="v">#{n_value}</div></div>
  <div class="card warn"><div class="k">No source / error</div><div class="v">#{n_other}</div></div>
  <div class="card"><div class="k">Nodes</div><div class="v">#{tot_nodes}</div></div>
  <div class="card"><div class="k">Links</div><div class="v">#{tot_links}</div></div>
  <div class="card"><div class="k">Subs</div><div class="v">#{tot_subs}</div></div>
  <div class="card #{tot_diff > 0 ? 'bad' : 'ok'}"><div class="k">Values differing</div>
    <div class="v">#{tot_diff}</div><div class="k">of #{tot_cmp} compared</div></div>
</div>

<div class="controls">
  <button id="only">Show problems only</button>
  <button id="det">Hide field detail</button>
  <button id="theme">Light / dark</button>
  <input id="q" placeholder="Filter by network name...">
  <span class="muted" id="count"></span>
</div>

<div class="tablewrap">
<table id="t"><thead><tr>
<th>Network</th><th>Status</th>
<th class="num">ICM nodes</th><th class="num">.inp</th><th class="num">&Delta;</th>
<th class="num">ICM links</th><th class="num">.inp</th><th class="num">&Delta;</th>
<th class="num">ICM subs</th><th class="num">.inp</th><th class="num">&Delta;</th>
<th class="num">Fields diff/cmp</th>
<th>Notes</th>
</tr></thead><tbody>
#{body}
</tbody></table>
</div>

<h2>Field mapping used</h2>
<div class="group">Candidate ICM field names were probed against a live row object; the first that resolved was used. Every field actually present is listed so the mapping can be corrected.</div>
#{mapping}

<h2>ICM object counts by table</h2>
<div class="group">Per-network counts for every sw_* table present. A dot means absent or empty.</div>
<div class="tablewrap">#{detail}</div>

<script>
var only = false, showDet = true;
function allRows(){ return Array.prototype.slice.call(document.querySelectorAll('#t tbody tr')); }
function apply(){
  var q = document.getElementById('q').value.toLowerCase();
  var shown = 0;
  allRows().forEach(function(tr){
    var st = tr.getAttribute('data-status');
    var isDetail = tr.classList.contains('detail');
    var okStatus = !only || st !== 'MATCH';
    var okText = tr.textContent.toLowerCase().indexOf(q) >= 0;
    var vis = okStatus && okText && (!isDetail || showDet);
    tr.style.display = vis ? '' : 'none';
    if (vis && !isDetail) shown++;
  });
  document.getElementById('count').textContent = shown + ' network(s) shown';
}
document.getElementById('only').onclick = function(){
  only = !only; this.textContent = only ? 'Show all' : 'Show problems only'; apply();
};
document.getElementById('det').onclick = function(){
  showDet = !showDet; this.textContent = showDet ? 'Hide field detail' : 'Show field detail'; apply();
};
document.getElementById('q').oninput = apply;
document.getElementById('theme').onclick = function(){
  var h = document.documentElement;
  h.setAttribute('data-theme', h.getAttribute('data-theme') === 'light' ? 'dark' : 'light');
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
log "SUMMARY  match=#{n_match}  count-mismatch=#{n_count}  value-mismatch=#{n_value}  other=#{n_other}"
log "         field values: #{tot_diff} differing of #{tot_cmp} compared"
log "Open: #{HTML_PATH}"
