# ============================================================================
# ICM Ruby API Probe (UI script)
# ============================================================================
# Answers three questions definitively by asking the live objects what methods
# they actually have, instead of guessing:
#
#   1. Is there a SWMM network -> InfoWorks network conversion/import method?
#      (UI equivalent: Network > Import > Model > from SWMM network...)
#   2. Can the .inp import run IN-PROCESS in the UI (import_all_sw_model_objects),
#      which would avoid the "blank network until ICM restarts" problem?
#   3. Is there any refresh/reload method to make the UI re-read the database?
#
# HOW TO USE:
#   1. Open the ICM database.
#   2. Select (single-click) an imported SWMM network in the tree so it is the
#      current network - or just run it; the script falls back to scanning.
#   3. Network > Run Ruby Script > select this file.
#   4. Read the report written to your Desktop: ICM_API_Probe.txt
#
# Read-only: this script does not modify the database.
# ============================================================================

# Pick the first writable location. %USERPROFILE%\Desktop does NOT exist when
# the Desktop is redirected to OneDrive, so try several candidates.
home = ENV['USERPROFILE'].to_s.gsub('\\', '/')
out_dir = [
  'C:/temp',
  File.join(home, 'OneDrive', 'Desktop'),
  File.join(home, 'Desktop'),
  home
].find { |d| Dir.exist?(d) } || 'C:/'

OUT_PATH = File.join(out_dir, 'ICM_API_Probe.txt')

$report = []
def say(line)
  puts line
  $report << line
end

say "=" * 70
say "ICM Ruby API Probe"
say "ICM version: #{begin WSApplication.version rescue 'unknown' end}"
say "UI mode:     #{begin WSApplication.ui? rescue (begin WSApplication.ui rescue 'unknown' end) end}"
say "=" * 70

db = WSApplication.current_database
if db.nil?
  say "ERROR: No database open."
else
  say "Database GUID: #{begin db.guid rescue 'n/a' end}"
end

# ---------------------------------------------------------------------------
# Helper: list methods matching any keyword
# ---------------------------------------------------------------------------
KEYWORDS = %w[import convert refresh reload reopen model_object new_ export commit validate open close]

def dump(label, obj)
  say ""
  say "-" * 70
  say "#{label}  (class: #{obj.class})"
  say "-" * 70

  begin
    all = obj.methods.map(&:to_s).sort
  rescue => e
    say "  Could not list methods: #{e.message}"
    return
  end

  # Drop the standard Ruby Object methods so only the ICM API remains.
  base = Object.new.methods.map(&:to_s)
  api  = all - base

  say "  Total ICM-specific methods: #{api.length}"

  KEYWORDS.each do |kw|
    hits = api.select { |m| m.downcase.include?(kw) }
    next if hits.empty?
    say "  [#{kw}] -> #{hits.join(', ')}"
  end

  say ""
  say "  FULL METHOD LIST:"
  api.each_slice(4) { |row| say "    #{row.join('  ')}" }
end

# ---------------------------------------------------------------------------
# 1. The database object
# ---------------------------------------------------------------------------
dump("WSDatabase (current_database)", db) if db

# ---------------------------------------------------------------------------
# 2. A Model Group and a SWMM network model object
# ---------------------------------------------------------------------------
if db
  group_obj = nil
  swmm_obj  = nil
  hw_obj    = nil

  queue = []
  db.root_model_objects.each { |o| queue << o }
  until queue.empty?
    o = queue.shift
    group_obj ||= o if o.type == 'Model Group'
    swmm_obj  ||= o if o.type == 'SWMM network'
    hw_obj    ||= o if o.type == 'Model Network'
    break if group_obj && swmm_obj && hw_obj
    begin
      o.children.each { |c| queue << c }
    rescue
      # some node types have no children
    end
  end

  say ""
  say "Found -> Model Group: #{group_obj ? group_obj.name : 'NONE'} | " \
      "SWMM network: #{swmm_obj ? swmm_obj.name : 'NONE'} | " \
      "Model Network: #{hw_obj ? hw_obj.name : 'NONE'}"

  dump("WSModelObject - Model Group", group_obj)     if group_obj
  dump("WSModelObject - SWMM network", swmm_obj)     if swmm_obj
  dump("WSModelObject - Model Network", hw_obj)      if hw_obj

  # -------------------------------------------------------------------------
  # 3. An OPEN network
  # -------------------------------------------------------------------------
  # An open SWMM network...
  open_sw = begin
    swmm_obj ? swmm_obj.open : nil
  rescue => e
    say "  (Could not open SWMM network: #{e.message})"
    nil
  end
  dump("WSOpenNetwork - OPEN SWMM NETWORK", open_sw) if open_sw

  # ...and an open InfoWorks network. THIS is the one that matters for
  # Network > Import > Model > from SWMM network..., because that UI command
  # acts on the open InfoWorks (Model Network) side.
  open_hw = begin
    hw_obj ? hw_obj.open : nil
  rescue => e
    say "  (Could not open InfoWorks network: #{e.message})"
    nil
  end
  dump("WSOpenNetwork - OPEN INFOWORKS NETWORK", open_hw) if open_hw

  open_net = open_hw || open_sw

  # -------------------------------------------------------------------------
  # 4. Direct answers
  # -------------------------------------------------------------------------
  say ""
  say "=" * 70
  say "ANSWERS"
  say "=" * 70

  checks = {
    "Group responds to import_all_sw_model_objects (in-process .inp import?)" =>
      (group_obj ? group_obj.respond_to?(:import_all_sw_model_objects) : nil),
    "Group responds to new_model_object" =>
      (group_obj ? group_obj.respond_to?(:new_model_object) : nil),
    "Open network responds to validate" =>
      (open_net ? open_net.respond_to?(:validate) : nil),
    "Open network responds to commit" =>
      (open_net ? open_net.respond_to?(:commit) : nil)
  }

  checks.each { |q, a| say format("  %-62s %s", q, a.nil? ? 'n/a' : a.to_s.upcase) }

  say ""
  say "  Methods anywhere containing 'convert', 'import' or 'swmm':"
  [db, group_obj, swmm_obj, hw_obj, open_sw, open_hw].compact.each do |o|
    api = (o.methods.map(&:to_s) - Object.new.methods.map(&:to_s))
    hits = api.select { |m| d = m.downcase
                            d.include?('convert') || d.include?('import') || d.include?('swmm') }
    say "    #{o.class}: #{hits.empty? ? '(none)' : hits.join(', ')}"
  end

  # Close anything this probe opened, so nothing is left locked.
  [open_sw, open_hw].compact.each { |n| begin n.close rescue nil end }
end

# ---------------------------------------------------------------------------
# Write report
# ---------------------------------------------------------------------------
begin
  File.open(OUT_PATH, 'w') { |f| f.puts $report.join("\n") }
  say ""
  say "Report written to: #{OUT_PATH}"
  WSApplication.message_box("API probe complete.\n\nReport written to:\n#{OUT_PATH}", "OK", "Information", false)
rescue => e
  say "Could not write report: #{e.message}"
end
