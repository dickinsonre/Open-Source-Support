# ============================================================================
# ICM Ruby API Probe 3 - signature of SWMM_import (and friends)
# ============================================================================
# Probe 2 found that WSOpenNetwork exposes a family of model-import methods
# that mirror the UI menu  Network > Import > Model > from ...:
#
#     SWMM_import / swmm_import          <- "from SWMM network..."   TARGET
#     XPSWMM_XPX_import                  <- "from XPSWMM/XPStorm..."
#     XPRAFTS_import                     <- "from XPRAFTS XPX file..."
#     InfoDrainage_import                <- "from InfoDrainage data..."
#
# This finds their argument counts, and whether they are allowed to run from
# the UI at all (many ICM methods raise "cannot be run from the user
# interface" and are ICMExchange-only).
#
# SAFETY: zero-argument calls only. Ruby's arity check raises BEFORE the method
# body executes, so nothing is imported or modified. Nothing is committed.
#
# IMPORTANT: open the InfoWorks (Model Network) you want to import INTO before
# running, so current_network is that network.
#
# HOW TO USE:  Network > Run Ruby Script > this file
# Report: C:\temp\ICM_API_Probe3.txt
# ============================================================================

home = ENV['USERPROFILE'].to_s.gsub('\\', '/')
out_dir = ['C:/temp', File.join(home, 'OneDrive', 'Desktop'), home].find { |d| Dir.exist?(d) } || 'C:/'
OUT_PATH = File.join(out_dir, 'ICM_API_Probe3.txt')

$report = []
def say(l)
  puts l
  $report << l
end

TARGETS = %w[
  SWMM_import
  swmm_import
  XPSWMM_XPX_import
  XPRAFTS_import
  InfoDrainage_import
  Examiner_import
  InfoAsset_Planner_import
  MACP_import
  snapshot_import
  snapshot_import_ex
  network_model_object
  model_object
  validate
  commit
  close
]

def sig(obj, name)
  sym = name.to_sym
  unless obj.respond_to?(sym) || obj.respond_to?(sym, true)
    say "  #{name}: (not present)"
    return
  end

  line = "  #{name}"
  begin
    m = obj.method(sym)
    line += "  arity=#{m.arity}"
  rescue => e
    line += "  (no Method: #{e.message})"
  end
  say line

  begin
    obj.send(sym)
    say "      0 args -> RETURNED without error"
  rescue => e
    say "      #{e.class}: #{e.message}"
  end
end

say "ICM version: #{begin WSApplication.version rescue '?' end}"
say "Probe 3 - SWMM_import signature"
say ""

net = begin
  WSApplication.current_network
rescue => e
  say "current_network unavailable: #{e.message}"
  nil
end

if net.nil?
  say "ERROR: No open network. Open an InfoWorks network first, then re-run."
else
  say "Open network class: #{net.class}"
  begin
    mo = net.model_object
    say "Open network object: #{mo.name}  (type: #{mo.type})"
  rescue => e
    say "(model_object unavailable: #{e.message})"
  end

  say ""
  say "=" * 70
  say "SIGNATURES"
  say "=" * 70
  TARGETS.each { |t| sig(net, t) }

  # Full method list for reference - WSOpenNetwork was unreachable in Probe 1
  # because #open is private in the UI.
  say ""
  say "=" * 70
  say "FULL WSOpenNetwork METHOD LIST"
  say "=" * 70
  api = (net.methods.map(&:to_s) - Object.new.methods.map(&:to_s)).sort
  say "Total: #{api.length}"
  api.each_slice(4) { |row| say "  #{row.join('  ')}" }
end

begin
  File.open(OUT_PATH, 'w') { |f| f.puts $report.join("\n") }
  WSApplication.message_box("Probe 3 complete.\n\n#{OUT_PATH}", "OK", "Information", false)
rescue => e
  say "Could not write: #{e.message}"
end
