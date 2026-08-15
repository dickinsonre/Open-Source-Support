# ============================================================================
# ICM API Probe 7 - what does SWMM_import(String, String) actually DO?
# ============================================================================
# Probe 6 established: receiver must be a SWMM network, and both arguments are
# Strings (model objects and Integers raise TypeError). But it returned nil for
# a non-existent path and for '', so "no exception" != "it worked". It must
# report problems through its log file.
#
# Two readings still standing:
#   (A) arg1 = database PATH of an InfoWorks network  -> InfoWorks -> SWMM
#       (model object paths are Strings, e.g. ">MODG~x>IWNET~y", so a String
#        argument does not rule this out - Probe 6 never tried hw.path)
#   (B) arg1 = a SWMM5 .inp FILE path                 -> file -> SWMM
#
# This probe runs BOTH against fresh scratch SWMM networks and measures the
# node/link counts afterwards. Whichever populates the network wins. It also
# dumps the import log, which is where ICM actually reports what happened.
#
# SAFETY: creates its own scratch networks, never commits, deletes them in an
# ensure block.
#
# Report: C:\temp\ICM_API_Probe7.txt
# ============================================================================

SCRATCH_GROUP = 'ZZ_API_Probe_Scratch'

home = ENV['USERPROFILE'].to_s.gsub('\\', '/')
out_dir = ['C:/temp', File.join(home, 'OneDrive', 'Desktop'), home].find { |d| Dir.exist?(d) } || 'C:/'
OUT_PATH = File.join(out_dir, 'ICM_API_Probe7.txt')

# A real SWMM5 .inp to test reading (B). Auto-discovered, override if needed.
INP_SEARCH = [
  'C:/Users/rober/GitHub/1729-SWMM5-Models-2030/Simon_EPA',
  'C:/temp'
]

$report = []
def say(l)
  puts l
  $report << l
end

def counts(net)
  n = 0; l = 0
  begin net.row_objects('_nodes').each { |_o| n += 1 } rescue n = -1 end
  begin net.row_objects('_links').each { |_o| l += 1 } rescue l = -1 end
  "nodes=#{n} links=#{l}"
end

def dump_log(path)
  if File.exist?(path)
    say "    --- import log (#{File.size(path)} bytes) ---"
    begin
      File.foreach(path).with_index do |line, i|
        say "      #{line.rstrip}"
        break if i >= 25
      end
    rescue => e
      say "      (unreadable: #{e.message})"
    end
    say "    --- end log ---"
  else
    say "    (no import log written at #{path})"
  end
end

say "=" * 70
say "ICM API Probe 7 - meaning of SWMM_import"
say "ICM version: #{begin WSApplication.version rescue '?' end}"
say "=" * 70

db = WSApplication.open

# Locate a real .inp
inp = nil
INP_SEARCH.each do |dir|
  next unless Dir.exist?(dir)
  hits = Dir.glob(File.join(dir, '*.inp'), File::FNM_CASEFOLD).sort
  if hits.any?
    inp = hits.first
    break
  end
end
say "Test .inp file : #{inp || 'NONE FOUND'}"

# Locate a source InfoWorks network
hw = nil
queue = []
db.root_model_objects.each { |o| queue << o }
until queue.empty?
  o = queue.shift
  if o.type == 'Model Network' && !o.name.start_with?('ZZ_Probe')
    hw = o
    break
  end
  begin o.children.each { |c| queue << c } rescue nil end
end
say "Source InfoWorks: #{hw ? "#{hw.name} (path #{hw.path})" : 'NONE FOUND'}"

group = nil
made  = []

begin
  db.root_model_objects.each { |o| group = o if o.type == 'Model Group' && o.name == SCRATCH_GROUP }
  group ||= db.new_model_object('Model Group', SCRATCH_GROUP)

  # -------------------------------------------------------------------------
  # TEST A - arg1 = InfoWorks network DATABASE PATH  (InfoWorks -> SWMM?)
  # -------------------------------------------------------------------------
  if hw
    say ""
    say "=" * 70
    say "TEST A: SWMM_import(infoworks_DB_PATH, log)"
    say "=" * 70
    logA = 'C:/temp/probe7_A.log'
    File.delete(logA) if File.exist?(logA)

    objA = group.new_model_object('SWMM network', 'ZZ_Probe_A')
    made << objA
    netA = objA.open
    say "  before: #{counts(netA)}"
    begin
      r = netA.SWMM_import(hw.path, logA)
      say "  returned: #{r.inspect}"
    rescue => e
      say "  #{e.class}: #{e.message}"
    end
    say "  after : #{counts(netA)}"
    dump_log(logA)
    begin netA.close rescue nil end
  end

  # -------------------------------------------------------------------------
  # TEST B - arg1 = real SWMM5 .inp FILE  (file -> SWMM?)
  # -------------------------------------------------------------------------
  if inp
    say ""
    say "=" * 70
    say "TEST B: SWMM_import(real .inp file, log)"
    say "=" * 70
    logB = 'C:/temp/probe7_B.log'
    File.delete(logB) if File.exist?(logB)

    objB = group.new_model_object('SWMM network', 'ZZ_Probe_B')
    made << objB
    netB = objB.open
    say "  before: #{counts(netB)}"
    begin
      r = netB.SWMM_import(inp.gsub('/', '\\'), logB)
      say "  returned: #{r.inspect}"
    rescue => e
      say "  #{e.class}: #{e.message}"
    end
    say "  after : #{counts(netB)}"
    dump_log(logB)
    begin netB.close rescue nil end
  end

  say ""
  say "=" * 70
  say "VERDICT"
  say "=" * 70
  say "  If TEST A populated the network -> SWMM_import does InfoWorks -> SWMM."
  say "  If only TEST B populated it     -> SWMM_import is just .inp -> SWMM,"
  say "                                     and SWMM -> InfoWorks has no Ruby API."

rescue => e
  say ""
  say "FATAL: #{e.class}: #{e.message}"
  say e.backtrace.first(6).join("\n")

ensure
  made.each do |o|
    begin
      o.delete
      say "Deleted scratch: #{o.name}"
    rescue => e
      say "Could not delete scratch: #{e.message}"
    end
  end

  begin
    if group
      n = 0
      group.children.each { |_c| n += 1 }
      if n == 0
        group.delete
        say "Scratch group deleted."
      else
        say "Scratch group kept (#{n} child object(s))."
      end
    end
  rescue => e
    say "Group cleanup: #{e.message}"
  end

  begin
    File.open(OUT_PATH, 'w') { |f| f.puts $report.join("\n") }
    puts "\nReport: #{OUT_PATH}"
  rescue => e
    puts "Could not write report: #{e.message}"
  end
end
