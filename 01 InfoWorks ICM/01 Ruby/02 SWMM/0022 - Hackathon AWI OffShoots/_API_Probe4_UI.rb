# ============================================================================
# ICM Ruby API Probe 4 - argument TYPES for SWMM_import(a, b)
# ============================================================================
# Probe 3 established:  SWMM_import arity = 2, and it is UI-callable (it raised
# ArgumentError, not "cannot be run from the user interface").
#
# This probe discovers WHAT the two arguments are, by calling it with several
# type combinations and reading ICM's complaint each time. Typical ICM errors
# name the offending parameter, e.g. "parameter 1 must be a model object".
#
# ---------------------------------------------------------------------------
# SAFETY - READ THIS
# ---------------------------------------------------------------------------
# Unlike Probes 1-3, this one CAN reach the method body, so it could in
# principle modify the open network. Precautions taken:
#   * It refuses to run unless the open network is an InfoWorks Model Network.
#   * It NEVER commits.
#   * It reports uncommitted_changes? before and after.
#   * If changes appear, it tells you to use Network > Revert (or run revert).
#
# STRONGLY RECOMMENDED: run this against a THROWAWAY InfoWorks network - e.g.
# create an empty one called "ZZ_ScratchInfoWorks" - not a real model.
#
# HOW TO USE:
#   1. Create/open a scratch InfoWorks (Model Network) network.
#   2. Network > Run Ruby Script > this file.
# Report: C:\temp\ICM_API_Probe4.txt
# ============================================================================

home = ENV['USERPROFILE'].to_s.gsub('\\', '/')
out_dir = ['C:/temp', File.join(home, 'OneDrive', 'Desktop'), home].find { |d| Dir.exist?(d) } || 'C:/'
OUT_PATH = File.join(out_dir, 'ICM_API_Probe4.txt')

$report = []
def say(l)
  puts l
  $report << l
end

say "ICM version: #{begin WSApplication.version rescue '?' end}"
say "Probe 4 - SWMM_import argument types"
say ""

db  = WSApplication.current_database
net = begin WSApplication.current_network rescue nil end

if net.nil?
  say "ERROR: no open network. Open a scratch InfoWorks network and re-run."
else
  mo = begin net.model_object rescue nil end
  say "Open network: #{mo ? mo.name : '?'}  (type: #{mo ? mo.type : '?'})"

  if mo && mo.type != 'Model Network'
    say ""
    say "!! The open network is a '#{mo.type}', not an InfoWorks 'Model Network'."
    say "!! SWMM_import imports SWMM data INTO an InfoWorks network, so please"
    say "!! open an InfoWorks network (ideally a scratch one) and re-run."
    say "!! Probing aborted - nothing was called."
  else
    # Find a source SWMM network to offer as an argument
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

    say "Candidate source SWMM network: #{swmm ? "#{swmm.name} (id #{swmm.id})" : 'NONE FOUND'}"

    before = begin mo.uncommitted_changes? rescue 'unknown' end
    say "Uncommitted changes BEFORE: #{before}"
    say ""
    say "=" * 70
    say "ATTEMPTS"
    say "=" * 70

    attempts = []
    attempts << ["nil, nil",                      lambda { net.SWMM_import(nil, nil) }]
    attempts << ["'', ''",                        lambda { net.SWMM_import('', '') }]
    if swmm
      attempts << ["swmm_object, nil",            lambda { net.SWMM_import(swmm, nil) }]
      attempts << ["swmm_object, ''",             lambda { net.SWMM_import(swmm, '') }]
      attempts << ["swmm_object, {}",             lambda { net.SWMM_import(swmm, {}) }]
      attempts << ["swmm_id(int), nil",           lambda { net.SWMM_import(swmm.id, nil) }]
      attempts << ["swmm_id(str), nil",           lambda { net.SWMM_import(swmm.id.to_s, nil) }]
      attempts << ["swmm_path, nil",              lambda { net.SWMM_import(swmm.path, nil) }]
    end
    attempts << ["'C:/temp/x.inp', nil",          lambda { net.SWMM_import('C:/temp/x.inp', nil) }]
    attempts << ["'C:/temp/x.inp', 'C:/temp/x.log'", lambda { net.SWMM_import('C:/temp/x.inp', 'C:/temp/x.log') }]

    attempts.each do |label, fn|
      begin
        r = fn.call
        say "  (#{label}) -> RETURNED #{r.inspect}"
      rescue => e
        say "  (#{label}) -> #{e.class}: #{e.message}"
      end
    end

    after = begin mo.uncommitted_changes? rescue 'unknown' end
    say ""
    say "Uncommitted changes AFTER: #{after}"
    if after == true && before != true
      say ""
      say "!! The network now has UNCOMMITTED CHANGES caused by this probe."
      say "!! Nothing was committed. Discard them with Network > Revert,"
      say "!! or delete the scratch network."
    end
  end
end

begin
  File.open(OUT_PATH, 'w') { |f| f.puts $report.join("\n") }
  WSApplication.message_box("Probe 4 complete.\n\n#{OUT_PATH}", "OK", "Information", false)
rescue => e
  say "Could not write: #{e.message}"
end
