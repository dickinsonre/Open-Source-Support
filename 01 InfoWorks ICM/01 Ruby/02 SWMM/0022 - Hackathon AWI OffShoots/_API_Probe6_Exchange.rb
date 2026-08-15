# ============================================================================
# ICM API Probe 6 - SWMM_import called ON a SWMM network (Exchange mode)
# ============================================================================
# Probe 5 result: SWMM_import always answered
#     RuntimeError: network is not a SWMM network
# even for (nil, nil) - so the check is on the RECEIVER, not the arguments.
# SWMM_import must be invoked on an open SWMM network.
#
# That leaves two readings, and this probe distinguishes them:
#
#   (A) InfoWorks -> SWMM : receiver is the SWMM network, arg1 is a source
#                           InfoWorks (Model Network) object.
#                           Matches the Innovyze doc "Importing from InfoWorks
#                           Network to SWMM Network". This is the REVERSE of
#                           what we want.
#
#   (B) .inp file -> SWMM : receiver is the SWMM network, arg1 is a SWMM5 text
#                           file path (the "from SWMM5 text file..." menu item).
#
# If (A), then SWMM -> InfoWorks may have no Ruby equivalent at all, and the
# answer to the original question is "not scriptable in this direction".
#
# SAFETY: creates its own scratch SWMM network, never commits, deletes it in an
# ensure block. Also cleans up the ZZ_API_Probe_Scratch group left by Probe 5
# (Probe 5's cleanup hit a bug: WSModelObjectCollection has no #to_a).
#
# Launch with _API_Probe5_Launch_UI.rb after pointing PROBE at this file, or:
#     ICMExchange.exe ICM_API_Probe6_Exchange.rb /ICM
#
# Report: C:\temp\ICM_API_Probe6.txt
# ============================================================================

SCRATCH_GROUP = 'ZZ_API_Probe_Scratch'
SCRATCH_NET   = 'ZZ_Probe_SWMM'

home = ENV['USERPROFILE'].to_s.gsub('\\', '/')
out_dir = ['C:/temp', File.join(home, 'OneDrive', 'Desktop'), home].find { |d| Dir.exist?(d) } || 'C:/'
OUT_PATH = File.join(out_dir, 'ICM_API_Probe6.txt')

$report = []
def say(l)
  puts l
  $report << l
end

# WSModelObjectCollection does not implement #to_a - count by iterating.
def child_count(obj)
  n = 0
  begin
    obj.children.each { |_c| n += 1 }
  rescue
    return -1
  end
  n
end

say "=" * 70
say "ICM API Probe 6 - SWMM_import ON a SWMM network"
say "ICM version: #{begin WSApplication.version rescue '?' end}"
say "=" * 70

db = WSApplication.open
say "Database GUID: #{begin db.guid rescue '?' end}"

# Find a source InfoWorks network (candidate arg for reading (A))
hw = nil
queue = []
db.root_model_objects.each { |o| queue << o }
until queue.empty?
  o = queue.shift
  if o.type == 'Model Network' && o.name != 'ZZ_Probe_InfoWorks'
    hw = o
    break
  end
  begin o.children.each { |c| queue << c } rescue nil end
end
say "Source InfoWorks network: #{hw ? "#{hw.name} (id #{hw.id})" : 'NONE FOUND'}"

group   = nil
scratch = nil
net     = nil

begin
  db.root_model_objects.each { |o| group = o if o.type == 'Model Group' && o.name == SCRATCH_GROUP }
  group ||= db.new_model_object('Model Group', SCRATCH_GROUP)
  say "Scratch group: #{group.name} (id #{group.id})"

  scratch = group.new_model_object('SWMM network', SCRATCH_NET)
  say "Scratch SWMM network: #{scratch.name} (id #{scratch.id}, type #{scratch.type})"

  net = scratch.open
  say "Opened: #{net.class}"

  say ""
  say "=" * 70
  say "ATTEMPTS - net.SWMM_import(arg1, arg2) where net IS a SWMM network"
  say "=" * 70

  log_path = 'C:/temp/probe6_import.log'
  attempts = []
  attempts << ["nil, nil",                       lambda { net.SWMM_import(nil, nil) }]
  if hw
    attempts << ["infoworks_object, nil",        lambda { net.SWMM_import(hw, nil) }]
    attempts << ["infoworks_object, log_path",   lambda { net.SWMM_import(hw, log_path) }]
    attempts << ["infoworks_id(int), nil",       lambda { net.SWMM_import(hw.id, nil) }]
    attempts << ["infoworks_object, {}",         lambda { net.SWMM_import(hw, {}) }]
  end
  attempts << ["'C:/temp/x.inp', nil",           lambda { net.SWMM_import('C:/temp/x.inp', nil) }]
  attempts << ["'C:/temp/x.inp', log_path",      lambda { net.SWMM_import('C:/temp/x.inp', log_path) }]
  attempts << ["'', ''",                         lambda { net.SWMM_import('', '') }]

  attempts.each do |label, fn|
    begin
      r = fn.call
      say "  (#{label})"
      say "      -> RETURNED #{r.inspect}   *** SIGNATURE ACCEPTED ***"
    rescue => e
      say "  (#{label})"
      say "      -> #{e.class}: #{e.message}"
    end
  end

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
  begin net.close if net rescue nil end

  begin
    if scratch
      scratch.delete
      say "Scratch SWMM network deleted."
    end
  rescue => e
    say "Could not delete scratch network: #{e.message}"
  end

  # Remove any leftover ZZ_Probe_InfoWorks from Probe 5, then the group itself.
  begin
    if group
      group.children.each do |c|
        if c.name == 'ZZ_Probe_InfoWorks'
          begin
            c.delete
            say "Removed leftover ZZ_Probe_InfoWorks from Probe 5."
          rescue => e
            say "Could not remove leftover: #{e.message}"
          end
        end
      end

      n = child_count(group)
      if n == 0
        group.delete
        say "Scratch group deleted."
      else
        say "Scratch group left in place (#{n} child object(s) remain)."
      end
    end
  rescue => e
    say "Group cleanup issue: #{e.message}"
  end

  begin
    File.open(OUT_PATH, 'w') { |f| f.puts $report.join("\n") }
    puts "\nReport: #{OUT_PATH}"
  rescue => e
    puts "Could not write report: #{e.message}"
  end
end
