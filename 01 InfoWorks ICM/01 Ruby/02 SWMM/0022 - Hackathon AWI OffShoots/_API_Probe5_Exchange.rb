# ============================================================================
# ICM Ruby API Probe 5 - SWMM_import argument types  (ICMExchange mode)
# ============================================================================
# Probe 4 proved SWMM_import is ICMExchange-only:
#     "The method cannot be run from the user interface"
# Ruby checks arity BEFORE ICM checks the UI gate, which is why the 0-arg call
# in Probe 3 returned ArgumentError and looked UI-callable. It is not.
#
# So this probe runs inside ICMExchange, where the method is permitted, and
# discovers the two argument types by trying combinations.
#
# SAFETY:
#   * Creates its OWN scratch InfoWorks network in a scratch Model Group.
#   * Never touches an existing model.
#   * Never commits.
#   * Deletes the scratch network and group on the way out (ensure block).
#
# Launch it with _API_Probe5_Launch_UI.rb, or manually:
#     ICMExchange.exe ICM_API_Probe5_Exchange.rb /ICM
#
# Report: C:\temp\ICM_API_Probe5.txt
# ============================================================================

SCRATCH_GROUP = 'ZZ_API_Probe_Scratch'
SCRATCH_NET   = 'ZZ_Probe_InfoWorks'

home = ENV['USERPROFILE'].to_s.gsub('\\', '/')
out_dir = ['C:/temp', File.join(home, 'OneDrive', 'Desktop'), home].find { |d| Dir.exist?(d) } || 'C:/'
OUT_PATH = File.join(out_dir, 'ICM_API_Probe5.txt')

$report = []
def say(l)
  puts l
  $report << l
end

say "=" * 70
say "ICM API Probe 5 - SWMM_import argument types (Exchange mode)"
say "ICM version: #{begin WSApplication.version rescue '?' end}"
say "=" * 70

db = WSApplication.open
say "Database GUID: #{begin db.guid rescue '?' end}"

# ---------------------------------------------------------------------------
# Locate a source SWMM network
# ---------------------------------------------------------------------------
swmm = nil
queue = []
db.root_model_objects.each { |o| queue << o }
until queue.empty?
  o = queue.shift
  if o.type == 'SWMM network'
    swmm = o
    break
  end
  begin o.children.each { |c| queue << c } rescue nil end
end

if swmm.nil?
  say "ERROR: no SWMM network found in this database - nothing to import from."
  File.open(OUT_PATH, 'w') { |f| f.puts $report.join("\n") }
  exit 1
end
say "Source SWMM network: #{swmm.name} (id #{swmm.id}, path #{begin swmm.path rescue '?' end})"

group   = nil
scratch = nil
net     = nil

begin
  # -------------------------------------------------------------------------
  # Build a disposable target
  # -------------------------------------------------------------------------
  db.root_model_objects.each { |o| group = o if o.type == 'Model Group' && o.name == SCRATCH_GROUP }
  group ||= db.new_model_object('Model Group', SCRATCH_GROUP)
  say "Scratch group: #{group.name} (id #{group.id})"

  scratch = group.new_model_object('Model Network', SCRATCH_NET)
  say "Scratch InfoWorks network: #{scratch.name} (id #{scratch.id}, type #{scratch.type})"

  net = scratch.open
  say "Opened scratch network: #{net.class}"

  # -------------------------------------------------------------------------
  # Try argument combinations
  # -------------------------------------------------------------------------
  say ""
  say "=" * 70
  say "ATTEMPTS  - SWMM_import(arg1, arg2)"
  say "=" * 70

  attempts = []
  attempts << ["nil, nil",                lambda { net.SWMM_import(nil, nil) }]
  attempts << ["swmm_object, nil",        lambda { net.SWMM_import(swmm, nil) }]
  attempts << ["swmm_object, ''",         lambda { net.SWMM_import(swmm, '') }]
  attempts << ["swmm_object, {}",         lambda { net.SWMM_import(swmm, {}) }]
  attempts << ["swmm_object, 'C:/temp/probe5_import.log'",
                                          lambda { net.SWMM_import(swmm, 'C:/temp/probe5_import.log') }]
  attempts << ["swmm_id(int), nil",       lambda { net.SWMM_import(swmm.id, nil) }]
  attempts << ["swmm_id(int), 'C:/temp/probe5_import.log'",
                                          lambda { net.SWMM_import(swmm.id, 'C:/temp/probe5_import.log') }]
  attempts << ["swmm_path(str), nil",     lambda { net.SWMM_import(swmm.path, nil) }]
  attempts << ["swmm_name(str), nil",     lambda { net.SWMM_import(swmm.name, nil) }]
  attempts << ["'C:/temp/x.inp', nil",    lambda { net.SWMM_import('C:/temp/x.inp', nil) }]

  attempts.each do |label, fn|
    begin
      r = fn.call
      say "  (#{label})"
      say "      -> RETURNED #{r.inspect}   *** LIKELY CORRECT SIGNATURE ***"
    rescue => e
      say "  (#{label})"
      say "      -> #{e.class}: #{e.message}"
    end
  end

  # Report any state change, but do NOT commit.
  begin
    say ""
    say "Uncommitted changes on scratch: #{scratch.uncommitted_changes?}"
  rescue => e
    say "(uncommitted_changes? unavailable: #{e.message})"
  end

rescue => e
  say ""
  say "FATAL: #{e.class}: #{e.message}"
  say e.backtrace.first(6).join("\n")

ensure
  # -------------------------------------------------------------------------
  # Tear down - leave the database exactly as we found it
  # -------------------------------------------------------------------------
  begin net.close if net rescue nil end
  begin
    if scratch
      scratch.delete
      say "Scratch network deleted."
    end
  rescue => e
    say "Could not delete scratch network: #{e.message}"
  end
  begin
    if group && group.children.to_a.empty?
      group.delete
      say "Scratch group deleted."
    end
  rescue => e
    say "Could not delete scratch group: #{e.message}"
  end

  begin
    File.open(OUT_PATH, 'w') { |f| f.puts $report.join("\n") }
    puts "\nReport: #{OUT_PATH}"
  rescue => e
    puts "Could not write report: #{e.message}"
  end
end
