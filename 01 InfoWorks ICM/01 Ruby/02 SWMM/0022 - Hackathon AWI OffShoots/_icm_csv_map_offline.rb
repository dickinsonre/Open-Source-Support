# ============================================================================
# Offline SWMM(.inp) -> InfoWorks(ICM CSV export) mapping analyser
# ============================================================================
# Runs on a plain Ruby install - no ICM needed. Feed it the .inp you imported
# and the CSV you exported from the manually converted InfoWorks network:
#
#   ruby icm_csv_map.rb Session1_user1.inp Session1_user1.csv [out.html]
#
# It matches objects by ID and, for every populated InfoWorks field, works out
# whether it is:
#   IDENTICAL / RATIO / OFFSET / LINEAR  to a SWMM quantity
#   CONSTANT                             (same value on every object)
#   DEFAULT                              (ICM flagged it '#D')
#   UNEXPLAINED                          (varies, unaccounted for)
#
# The '#D' flag is ICM's own marker for "this came from a default, not from
# your data", which makes the DEFAULT class authoritative rather than inferred.
# ============================================================================

require 'csv'

TOL       = 0.001
ABS_EPS   = 1e-9
MIN_N     = 5
CONFIDENT = 0.98

# ---------------------------------------------------------------------------
# ICM CSV export: '**** table' then ObjectTable/FieldDescription/UserUnits rows
# ---------------------------------------------------------------------------
def parse_icm_csv(path)
  tables = {}
  cur = nil
  File.foreach(path) do |raw|
    line = raw.to_s.scrub('').rstrip
    next if line.empty?

    if line.start_with?('**** ')
      cur = line[5..-1].strip
      tables[cur] = { fields: [], units: [], rows: [] }
      next
    end
    next unless cur

    cells = begin
      CSV.parse_line(line) || []
    rescue
      line.split(',')
    end
    next if cells.empty?
    tag = cells[0].to_s

    if tag == 'ObjectTable'
      tables[cur][:fields] = cells[1..-1].map { |c| c.to_s }
    elsif tag == 'FieldDescription'
      next
    elsif tag == 'UserUnits'
      tables[cur][:units] = cells[1..-1].map { |c| c.to_s }
    else
      f = tables[cur][:fields]
      next if f.empty?
      row = {}
      vals = cells[1..-1] || []
      f.each_with_index { |name, i| row[name] = vals[i] }
      tables[cur][:rows] << row
    end
  end
  tables
end

# ---------------------------------------------------------------------------
# SWMM .inp
# ---------------------------------------------------------------------------
NODE_SECS = %w[JUNCTIONS OUTFALLS STORAGE DIVIDERS]
LINK_SECS = %w[CONDUITS PUMPS ORIFICES WEIRS OUTLETS]
SUB_SECS  = %w[SUBCATCHMENTS]
KEEP      = NODE_SECS + LINK_SECS + SUB_SECS + %w[XSECTIONS COORDINATES]

NODE_COLS = {
  'JUNCTIONS' => { invert: 1, max_depth: 2, init_depth: 3, sur_depth: 4, ponded: 5 },
  'OUTFALLS'  => { invert: 1 },
  'STORAGE'   => { invert: 1, max_depth: 2, init_depth: 3 }
}
LINK_COLS = { 'CONDUITS' => { length: 3, roughness: 4, in_offset: 5, out_offset: 6 } }
SUB_COLS  = { 'SUBCATCHMENTS' => { area: 3, imperv: 4, width: 5, slope: 6 } }

def parse_inp(path)
  nodes = {}; links = {}; subs = {}
  cur = nil
  File.foreach(path) do |raw|
    line = raw.to_s.scrub('').split(';').first.to_s.strip
    next if line.empty?
    if line.start_with?('[')
      n = line.gsub(/[\[\]]/, '').strip.upcase
      cur = KEEP.include?(n) ? n : nil
      next
    end
    next unless cur
    tok = line.split(/\s+/)
    next if tok.empty?
    id = tok[0]

    if (c = NODE_COLS[cur])
      h = nodes[id] ||= {}
      c.each { |k, i| h[k] = tok[i].to_f if tok[i] }
    elsif (c = LINK_COLS[cur])
      h = links[id] ||= {}
      c.each { |k, i| h[k] = tok[i].to_f if tok[i] }
    elsif (c = SUB_COLS[cur])
      h = subs[id] ||= {}
      c.each { |k, i| h[k] = tok[i].to_f if tok[i] }
    elsif cur == 'XSECTIONS'
      g = tok[2]
      # IRREGULAR cross-sections put a transect NAME in Geom1, not a number
      gv = g ? num(g) : nil
      (links[id] ||= {})[:geom1] = gv if gv
    elsif cur == 'COORDINATES'
      h = nodes[id] ||= {}
      h[:x] = tok[1].to_f if tok[1]
      h[:y] = tok[2].to_f if tok[2]
    end
  end
  [nodes, links, subs]
end

# ---------------------------------------------------------------------------
def median(a)
  return nil if a.empty?
  s = a.sort
  n = s.length
  n.odd? ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2.0
end

def close?(x, y)
  d = (x - y).abs
  return true if d <= ABS_EPS
  den = y.abs > ABS_EPS ? y.abs : (x.abs > ABS_EPS ? x.abs : 1.0)
  (d / den) <= TOL
end

NUMERIC_RE = /\A[-+]?(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?\z/

def num(v)
  return nil if v.nil?
  s = v.to_s.strip
  return nil if s.empty?
  # ICM writes numbers as "10." and "0." - Float() REJECTS a trailing dot with
  # no digits after it, so validate the shape then use to_f.
  return nil unless s =~ NUMERIC_RE
  s.to_f
end

# Find the best relationship between one ICM field and the SWMM quantities
def relate(icm_vals, swmm_by_key)
  present = icm_vals.compact
  return { kind: 'EMPTY' } if present.empty?

  if present.length >= MIN_N && present.all? { |v| close?(v, present[0]) }
    return { kind: 'CONSTANT', value: present[0], n: present.length, score: 1.0 }
  end

  best = nil
  swmm_by_key.each do |sk, svals|
    pairs = []
    icm_vals.each_with_index do |a, i|
      b = svals[i]
      pairs << [a, b] if a && b
    end
    next if pairs.length < MIN_N
    n = pairs.length

    hits = pairs.count { |a, b| close?(a, b) }
    sc = hits.to_f / n
    best = { kind: 'IDENTICAL', swmm: sk, score: sc, n: n } if best.nil? || sc > best[:score]

    rs = pairs.select { |_a, b| b.abs > ABS_EPS }.map { |a, b| a / b }
    if rs.length >= MIN_N
      k = median(rs)
      if k && k.abs > ABS_EPS
        hits = pairs.count { |a, b| close?(a, k * b) }
        sc = hits.to_f / n
        best = { kind: 'RATIO', swmm: sk, k: k, score: sc, n: n } if sc > best[:score]
      end
    end

    c = median(pairs.map { |a, b| a - b })
    if c && c.abs > ABS_EPS
      hits = pairs.count { |a, b| close?(a, b + c) }
      sc = hits.to_f / n
      best = { kind: 'OFFSET', swmm: sk, c: c, score: sc, n: n } if sc > best[:score]
    end

    sx = sy = sxx = sxy = 0.0
    pairs.each { |a, b| sx += b; sy += a; sxx += b * b; sxy += b * a }
    den = (n * sxx) - (sx * sx)
    if den.abs > ABS_EPS
      m = ((n * sxy) - (sx * sy)) / den
      q = (sy - m * sx) / n
      hits = pairs.count { |a, b| close?(a, m * b + q) }
      sc = hits.to_f / n
      best = { kind: 'LINEAR', swmm: sk, m: m, c: q, score: sc, n: n } if sc > best[:score] && m.abs > ABS_EPS
    end
  end

  return { kind: 'UNEXPLAINED', score: best ? best[:score] : 0.0 } if best.nil? || best[:score] < CONFIDENT
  best
end

def sig(r)
  case r[:kind]
  when 'IDENTICAL' then "= swmm.#{r[:swmm]}"
  when 'RATIO'     then "= swmm.#{r[:swmm]} * #{r[:k].round(6)}"
  when 'OFFSET'    then "= swmm.#{r[:swmm]} + #{r[:c].round(6)}"
  when 'LINEAR'    then "= #{r[:m].round(6)} * swmm.#{r[:swmm]} + #{r[:c].round(6)}"
  when 'CONSTANT'  then "constant #{r[:value]}"
  when 'EMPTY'     then 'empty'
  else                  'unexplained'
  end
end

# ---------------------------------------------------------------------------
inp_path = ARGV[0]
csv_path = ARGV[1]
abort "usage: ruby icm_csv_map.rb <file.inp> <export.csv> [out.html]" unless inp_path && csv_path

nodes, links, subs = parse_inp(inp_path)
tables = parse_icm_csv(csv_path)

puts "SWMM  : #{File.basename(inp_path)}  nodes=#{nodes.size} links=#{links.size} subs=#{subs.size}"
puts "ICM   : #{File.basename(csv_path)}  tables=#{tables.size}"
puts

SPECS = [
  ['hw_node',         'node_id',         nodes],
  ['hw_conduit',      'us_node_id',      links],
  ['hw_subcatchment', 'subcatchment_id', subs]
]

all_results = []

SPECS.each do |tbl, idfield, swmm_vals|
  t = tables[tbl]
  next if t.nil? || t[:rows].empty?

  # locate the ID column: prefer the named one, else the first field
  idf = t[:fields].include?(idfield) ? idfield : t[:fields][0]

  # ICM conduit IDs are us_node_id + link_suffix; the .inp link name is the
  # asset_id, so prefer asset_id when it is populated.
  if tbl == 'hw_conduit'
    idf = 'asset_id' if t[:fields].include?('asset_id') &&
                        t[:rows].count { |r| !r['asset_id'].to_s.strip.empty? } > (t[:rows].length / 2)
  end

  ids = t[:rows].map { |r| r[idf].to_s }
  matched = ids.count { |i| swmm_vals.key?(i) }
  puts "== #{tbl}  (#{t[:rows].length} rows, id column '#{idf}', #{matched} matched to SWMM)"

  if matched < MIN_N
    puts "   too few matches - skipping\n\n"
    next
  end

  # SWMM quantity series aligned to ICM row order
  keys = swmm_vals.values.map(&:keys).flatten.uniq
  swmm_series = {}
  keys.each do |k|
    swmm_series[k] = ids.map { |i| (swmm_vals[i] || {})[k] }
  end

  flagged_default = {}
  results = []

  t[:fields].each do |f|
    next if f.end_with?('_flag')
    vals = t[:rows].map { |r| num(r[f]) }
    next if vals.compact.empty?

    # is this field marked as an ICM default?
    fl = "#{f}_flag"
    if t[:fields].include?(fl)
      dcount = t[:rows].count { |r| r[fl].to_s.strip == '#D' }
      flagged_default[f] = dcount if dcount > 0
    end

    r = relate(vals, swmm_series)
    unit = t[:units][t[:fields].index(f)].to_s
    results << { table: tbl, field: f, unit: unit, res: r,
                 defaults: flagged_default[f] || 0, rows: t[:rows].length }
  end

  # report
  order = { 'IDENTICAL' => 0, 'RATIO' => 1, 'OFFSET' => 2, 'LINEAR' => 3,
            'CONSTANT' => 4, 'UNEXPLAINED' => 5, 'EMPTY' => 6 }
  results.sort_by! { |x| [order[x[:res][:kind]] || 9, x[:field]] }

  results.each do |x|
    next if x[:res][:kind] == 'EMPTY'
    d = x[:defaults] > 0 ? "  [#D x#{x[:defaults]}]" : ''
    u = x[:unit].empty? ? '' : " (#{x[:unit]})"
    printf("   %-34s %-12s %-42s%s%s\n",
           x[:field], x[:res][:kind], sig(x[:res]), u, d)
  end
  puts

  all_results.concat(results)
end

# summary
counts = Hash.new(0)
all_results.each { |x| counts[x[:res][:kind]] += 1 }
puts '== SUMMARY =='
counts.sort_by { |k, _| k }.each { |k, v| puts "   #{k}: #{v}" }
