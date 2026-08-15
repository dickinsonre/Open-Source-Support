# ============================================================================
# SWMM -> ICM InfoWorks PRE-FLIGHT CHECKER            (offline, no ICM needed)
# ============================================================================
#   ruby swmm_icm_preflight.rb <folder-with-inp> [more folders...]
#
# Scans SWMM5 .inp files for constructs that are perfectly legal in SWMM but
# that ICM's InfoWorks importer either mangles or that ICM validation rejects.
# Run it BEFORE doing the manual conversions so you know which models will
# throw errors and why.
#
# Every rule below was derived from observed ICM 2027 behaviour on real
# conversions, not from documentation:
#
#  E9001-roof  Gated outfall (Gated = YES)
#              ICM's converter writes a nonsense chamber_roof (~1e6) and its
#              own validator then rejects it: "Value too large. Maximum Value
#              is 9999.000 m AD". Observed on 3 of 3 gated outfalls; 0 of 3
#              non-gated outfalls in the same model.
#
#  E9001-len   Conduit shorter than 1.0 m AFTER unit conversion
#              ICM enforces a 1.0 m minimum. A US-units model measured in feet
#              can be legal in SWMM and illegal in ICM: 2.53 ft = 0.771 m.
#
#  E2310       Subcatchment draining directly to an Outfall
#              Legal in SWMM, rejected by ICM: "Subcatchments cannot drain to
#              nodes of type 'Outfall', 'Outfall 2D' or 'Connect 2D'".
#
#  W2075       Conduit roughness outside the suggested range (warning only)
#
# Output: preflight table on stdout, plus C:\temp\SWMM_ICM_Preflight.html
# ============================================================================

FT_TO_M      = 0.3048
MIN_LEN_M    = 1.0
ROUGH_LOW    = 0.009
ROUGH_HIGH   = 0.1
US_UNITS     = %w[CFS GPM MGD]     # everything else is metric

def esc(s)
  s.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
end

NRE = /\A[-+]?(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?\z/
def num(v)
  s = v.to_s.strip
  (s =~ NRE) ? s.to_f : nil
end

def scan(path)
  r = {
    file: path, units: nil, us: false,
    outfalls: {}, gated: [], conduits: 0, short: [], subs_to_outfall: [],
    rough_low: [], rough_high: [], error: nil
  }
  cur = nil

  begin
    File.foreach(path) do |raw|
      line = raw.to_s.scrub('').split(';').first.to_s.strip
      next if line.empty?

      if line.start_with?('[')
        cur = line.gsub(/[\[\]]/, '').strip.upcase
        next
      end

      tok = line.split(/\s+/)
      next if tok.empty?

      case cur
      when 'OPTIONS'
        if tok[0].to_s.upcase == 'FLOW_UNITS'
          r[:units] = tok[1].to_s.upcase
          r[:us] = US_UNITS.include?(r[:units])
        end
      when 'OUTFALLS'
        r[:outfalls][tok[0]] = true
        # Name Elevation Type [StageData] Gated [RouteTo] - Gated is the
        # first YES/NO token on the line.
        gated = tok[1..-1].to_a.find { |t| %w[YES NO].include?(t.to_s.upcase) }
        r[:gated] << tok[0] if gated.to_s.upcase == 'YES'
      when 'CONDUITS'
        r[:conduits] += 1
        len = num(tok[3])
        rough = num(tok[4])
        if len
          m = r[:us] ? len * FT_TO_M : len
          r[:short] << [tok[0], len, m.round(4)] if m < MIN_LEN_M
        end
        if rough && rough > 0
          r[:rough_low]  << [tok[0], rough] if rough < ROUGH_LOW
          r[:rough_high] << [tok[0], rough] if rough > ROUGH_HIGH
        end
      when 'SUBCATCHMENTS'
        r[:subs_to_outfall] << [tok[0], tok[2]]   # resolved after the file is read
      end
    end
  rescue => e
    r[:error] = e.message
    return r
  end

  # keep only subcatchments whose outlet really is an outfall
  r[:subs_to_outfall] = r[:subs_to_outfall].select { |_s, o| r[:outfalls][o] }
  r
end

# ---------------------------------------------------------------------------
dirs = ARGV.empty? ? ['.'] : ARGV
files = []
dirs.each do |d|
  files.concat(Dir.glob(File.join(d, '**', '*.inp'), File::FNM_CASEFOLD).select { |f| File.file?(f) })
end
files.sort!
abort 'No .inp files found.' if files.empty?

results = files.map { |f| scan(f) }

def issues(r)
  n = 0
  n += r[:gated].length
  n += r[:short].length
  n += r[:subs_to_outfall].length
  n
end

clean = results.count { |r| issues(r) == 0 && r[:error].nil? }
puts format('%-52s %-6s %6s %6s %6s %6s', 'FILE', 'UNITS', 'GATED', 'SHORT', 'SUB>OF', 'ROUGH')
puts '-' * 92
results.each do |r|
  next if issues(r) == 0 && r[:rough_low].empty? && r[:rough_high].empty?
  puts format('%-52s %-6s %6d %6d %6d %6d',
              File.basename(r[:file])[0, 50], r[:units] || '?',
              r[:gated].length, r[:short].length,
              r[:subs_to_outfall].length, r[:rough_low].length + r[:rough_high].length)
end
puts '-' * 92
puts "#{files.length} file(s) scanned, #{clean} with no blocking issues"

# ---------------------------------------------------------------------------
# HTML
# ---------------------------------------------------------------------------
home    = ENV['USERPROFILE'].to_s.gsub('\\', '/')
out_dir = ['C:/temp', File.join(home, 'OneDrive', 'Desktop'), home].find { |d| Dir.exist?(d) } || '.'
html_path = File.join(out_dir, 'SWMM_ICM_Preflight.html')

tot_gated = results.inject(0) { |a, r| a + r[:gated].length }
tot_short = results.inject(0) { |a, r| a + r[:short].length }
tot_sub   = results.inject(0) { |a, r| a + r[:subs_to_outfall].length }
tot_rough = results.inject(0) { |a, r| a + r[:rough_low].length + r[:rough_high].length }
n_us      = results.count { |r| r[:us] }

rows = ''
results.each do |r|
  blocking = issues(r)
  warnonly = r[:rough_low].length + r[:rough_high].length
  cls = r[:error] ? 'warn' : (blocking > 0 ? 'bad' : (warnonly > 0 ? 'mid' : 'ok'))
  status = r[:error] ? 'READ ERROR' : (blocking > 0 ? 'WILL ERROR' : (warnonly > 0 ? 'warnings' : 'clean'))

  det = []
  unless r[:gated].empty?
    det << 'E9001 chamber roof - gated outfall(s): ' + esc(r[:gated].first(6).join(', ')) +
           (r[:gated].length > 6 ? " +#{r[:gated].length - 6} more" : '')
  end
  unless r[:short].empty?
    ex = r[:short].first(5).map { |id, raw, m| "#{esc(id)} #{raw}#{r[:us] ? 'ft' : 'm'}=#{m}m" }.join(' &middot; ')
    det << "E9001 length &lt; 1.0 m: #{ex}" + (r[:short].length > 5 ? " +#{r[:short].length - 5} more" : '')
  end
  unless r[:subs_to_outfall].empty?
    ex = r[:subs_to_outfall].first(5).map { |s, o| "#{esc(s)} &rarr; #{esc(o)}" }.join(' &middot; ')
    det << "E2310 subcatchment drains to outfall: #{ex}"
  end
  unless r[:rough_low].empty?
    det << 'W2075 roughness low: ' + r[:rough_low].first(5).map { |id, v| "#{esc(id)}=#{v}" }.join(' &middot; ')
  end
  unless r[:rough_high].empty?
    det << 'W2075 roughness high: ' + r[:rough_high].first(5).map { |id, v| "#{esc(id)}=#{v}" }.join(' &middot; ')
  end
  det << "read error: #{esc(r[:error])}" if r[:error]

  rows += '<tr class="' + cls + '" data-status="' + status + '">'
  rows += '<td class="name">' + esc(File.basename(r[:file])) + '</td>'
  rows += '<td><span class="pill ' + cls + '">' + status + '</span></td>'
  rows += '<td>' + esc(r[:units] || '?') + (r[:us] ? ' <span class="muted">(US)</span>' : '') + '</td>'
  rows += '<td class="num">' + r[:conduits].to_s + '</td>'
  rows += '<td class="num' + (r[:gated].empty? ? ' muted' : ' delta') + '">' + r[:gated].length.to_s + '</td>'
  rows += '<td class="num' + (r[:short].empty? ? ' muted' : ' delta') + '">' + r[:short].length.to_s + '</td>'
  rows += '<td class="num' + (r[:subs_to_outfall].empty? ? ' muted' : ' delta') + '">' + r[:subs_to_outfall].length.to_s + '</td>'
  rows += '<td class="num muted">' + (r[:rough_low].length + r[:rough_high].length).to_s + '</td>'
  rows += '<td class="notes">' + det.join('<br>') + '</td>'
  rows += "</tr>\n"
end

html = <<HTMLDOC
<!doctype html>
<html lang="en" data-theme="dark"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>SWMM to ICM Pre-flight</title>
<style>
:root{--bg:#0f172a;--panel:#1e293b;--line:#334155;--text:#e2e8f0;--muted:#94a3b8;
  --ok:#22c55e;--bad:#f87171;--mid:#fb923c;--warn:#fbbf24}
html[data-theme="light"]{--bg:#f8fafc;--panel:#fff;--line:#e2e8f0;--text:#0f172a;--muted:#64748b;
  --ok:#15803d;--bad:#b91c1c;--mid:#c2410c;--warn:#a16207}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--text);
  font:14px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif}
.wrap{max-width:1500px;margin:0 auto;padding:28px 20px 80px}
h1{font-size:22px;margin:0 0 4px}
.meta{color:var(--muted);font-size:13px;margin-bottom:20px}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(140px,1fr));gap:12px;margin-bottom:20px}
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
  letter-spacing:.05em;color:var(--muted)}
td.num{text-align:right;font-variant-numeric:tabular-nums}
td.delta{color:var(--bad);font-weight:600}
.muted,td.muted{color:var(--muted)}
td.name{white-space:normal;min-width:230px}
td.notes{white-space:normal;color:var(--muted);min-width:380px;font-size:12px}
tr.ok td:first-child{box-shadow:inset 3px 0 0 var(--ok)}
tr.bad td:first-child{box-shadow:inset 3px 0 0 var(--bad)}
tr.mid td:first-child{box-shadow:inset 3px 0 0 var(--mid)}
tr.warn td:first-child{box-shadow:inset 3px 0 0 var(--warn)}
.pill{padding:2px 8px;border-radius:999px;font-size:11px;font-weight:600;border:1px solid}
.pill.ok{color:var(--ok);border-color:var(--ok)}
.pill.bad{color:var(--bad);border-color:var(--bad)}
.pill.mid{color:var(--mid);border-color:var(--mid)}
.pill.warn{color:var(--warn);border-color:var(--warn)}
.rules{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:14px;margin-top:22px}
.rules li{margin-bottom:6px}
code{background:rgba(148,163,184,.15);padding:1px 5px;border-radius:4px}
</style></head><body><div class="wrap">

<h1>SWMM &rarr; ICM InfoWorks pre-flight</h1>
<div class="meta">#{Time.now.strftime('%Y-%m-%d %H:%M')} &middot; #{files.length} .inp file(s) &middot; #{n_us} in US units</div>

<div class="cards">
  <div class="card ok"><div class="k">Clean</div><div class="v">#{clean}</div></div>
  <div class="card bad"><div class="k">Gated outfalls</div><div class="v">#{tot_gated}</div></div>
  <div class="card bad"><div class="k">Conduits &lt; 1 m</div><div class="v">#{tot_short}</div></div>
  <div class="card bad"><div class="k">Sub &rarr; outfall</div><div class="v">#{tot_sub}</div></div>
  <div class="card mid"><div class="k">Roughness warnings</div><div class="v">#{tot_rough}</div></div>
</div>

<div class="controls">
  <button id="only">Show problems only</button>
  <button id="theme">Light / dark</button>
  <input id="q" placeholder="Filter by file name...">
  <span class="muted" id="count"></span>
</div>

<div class="tablewrap">
<table id="t"><thead><tr>
<th>File</th><th>Status</th><th>Units</th><th class="num">Conduits</th>
<th class="num">Gated OF</th><th class="num">&lt;1m</th><th class="num">Sub&rarr;OF</th><th class="num">Rough</th>
<th>Detail</th>
</tr></thead><tbody>
#{rows}
</tbody></table>
</div>

<div class="rules">
<b>Rules, and where they came from</b>
<ul>
<li><code>E9001</code> <b>gated outfall</b> - ICM's importer writes a nonsense <code>chamber_roof</code> (~1e6) for
outfalls with <code>Gated = YES</code>, then its own validator rejects it (max 9999 m AD).
Measured: 3 of 3 gated outfalls broken, 0 of 3 non-gated in the same model.</li>
<li><code>E9001</code> <b>conduit &lt; 1.0 m</b> - ICM enforces a 1 m minimum. In a US-units model the
<code>.inp</code> value is in feet, so 2.53 ft becomes 0.771 m and fails. Legal in SWMM, illegal in ICM.</li>
<li><code>E2310</code> <b>subcatchment draining to an outfall</b> - allowed by SWMM, rejected by ICM.</li>
<li><code>W2075</code> <b>roughness</b> outside #{ROUGH_LOW}-#{ROUGH_HIGH} - warning only, conversion still succeeds.</li>
</ul>
</div>

<script>
var only=false;
function rowsOf(){return Array.prototype.slice.call(document.querySelectorAll('#t tbody tr'));}
function apply(){
  var q=document.getElementById('q').value.toLowerCase(), n=0;
  rowsOf().forEach(function(tr){
    var st=tr.getAttribute('data-status');
    var vis=(!only || st!=='clean') && tr.textContent.toLowerCase().indexOf(q)>=0;
    tr.style.display=vis?'':'none'; if(vis)n++;
  });
  document.getElementById('count').textContent=n+' shown';
}
document.getElementById('only').onclick=function(){only=!only;
  this.textContent=only?'Show all':'Show problems only';apply();};
document.getElementById('q').oninput=apply;
document.getElementById('theme').onclick=function(){var h=document.documentElement;
  h.setAttribute('data-theme',h.getAttribute('data-theme')==='light'?'dark':'light');};
apply();
</script>
</div></body></html>
HTMLDOC

begin
  File.open(html_path, 'w') { |f| f.write(html) }
  puts "HTML: #{html_path}"
rescue => e
  puts "HTML failed: #{e.message}"
end
