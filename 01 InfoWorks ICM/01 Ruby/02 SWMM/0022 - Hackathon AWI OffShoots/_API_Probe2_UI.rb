# ============================================================================
# ICM Ruby API Probe 2 - method SIGNATURES
# ============================================================================
# Probe 1 found that no 'convert' method exists, but that import_data() does -
# on both Model Groups and network objects. That is the most likely Ruby
# equivalent of:  Network > Import > Model > from SWMM network...
#
# This script discovers the SIGNATURE of the candidate methods by:
#   a) asking Ruby for .arity and .parameters
#   b) calling each with ZERO arguments inside a rescue - ICM's ArgumentError
#      reports "wrong number of arguments (given 0, expected N)", which reveals
#      the argument count without performing any import.
#
# SAFETY: only zero-argument calls are attempted. Ruby raises ArgumentError on
# the arity check BEFORE the method body runs, so nothing is imported, created,
# modified or deleted. This script does not commit anything.
#
# HOW TO USE:  Network > Run Ruby Script > this file
# Report: C:\temp\ICM_API_Probe2.txt
# ============================================================================

home = ENV['USERPROFILE'].to_s.gsub('\\', '/')
out_dir = ['C:/temp', File.join(home, 'OneDrive', 'Desktop'), home].find { |d| Dir.exist?(d) } || 'C:/'
OUT_PATH = File.join(out_dir, 'ICM_API_Probe2.txt')

$report = []
def say(l)
  puts l
  $report << l
end

CANDIDATES = %w[
  import_data
  import_all_sw_model_objects
  import_new_sw_model_object
  import_new_model_object
  odic_import
  odic_import_ex
  export
  csv_import
  update
  compare
]

def probe(label, obj)
  say ""
  say "=" * 70
  say "#{label}   (#{obj.class})"
  say "=" * 70

  CANDIDATES.each do |name|
    sym = name.to_sym
    next unless obj.respond_to?(sym) || obj.respond_to?(sym, true)

    line = "  #{name}"

    # Arity / parameters (often unhelpful for C methods, but free to ask)
    begin
      m = obj.method(sym)
      line += "  arity=#{m.arity}"
      begin
        line += "  params=#{m.parameters.inspect}"
      rescue
        # some builtins have no parameter info
      end
    rescue => e
      line += "  (no Method object: #{e.message})"
    end
    say line

    # Zero-arg call: the ArgumentError text reveals the real argument count.
    begin
      obj.send(sym)
      say "      called with 0 args -> RETURNED (no error)"
    rescue ArgumentError => e
      say "      ArgumentError: #{e.message}"
    rescue TypeError => e
      say "      TypeError: #{e.message}"
    rescue NotImplementedError => e
      say "      NotImplementedError: #{e.message}"
    rescue RuntimeError => e
      say "      RuntimeError: #{e.message}"
    rescue => e
      say "      #{e.class}: #{e.message}"
    end
  end
end

say "ICM version: #{begin WSApplication.version rescue '?' end}"
say "Probe 2 - method signatures"

db = WSApplication.current_database
if db.nil?
  say "ERROR: no database open"
else
  group = nil
  swmm  = nil
  hw    = nil

  queue = []
  db.root_model_objects.each { |o| queue << o }
  until queue.empty?
    o = queue.shift
    group ||= o if o.type == 'Model Group'
    swmm  ||= o if o.type == 'SWMM network'
    hw    ||= o if o.type == 'Model Network'
    break if group && swmm && hw
    begin
      o.children.each { |c| queue << c }
    rescue
    end
  end

  say ""
  say "Model Group   : #{group ? group.name : 'NONE'}"
  say "SWMM network  : #{swmm ? swmm.name : 'NONE'}"
  say "Model Network : #{hw ? hw.name : 'NONE'}"

  probe("MODEL GROUP", group)          if group
  probe("SWMM NETWORK object", swmm)   if swmm
  probe("MODEL NETWORK object", hw)    if hw

  # The currently open network in the UI (if the user has one open).
  cur = begin
    WSApplication.current_network
  rescue => e
    say "\n(current_network unavailable: #{e.message})"
    nil
  end

  if cur
    say ""
    say "Current open network class: #{cur.class}"
    api = (cur.methods.map(&:to_s) - Object.new.methods.map(&:to_s)).sort
    say "Open-network methods containing import/convert/swmm/model:"
    hits = api.select { |m| d = m.downcase
                            d.include?('import') || d.include?('convert') ||
                            d.include?('swmm')   || d.include?('model') }
    say "  #{hits.empty? ? '(none)' : hits.join(', ')}"
    probe("CURRENT OPEN NETWORK", cur)
  end
end

begin
  File.open(OUT_PATH, 'w') { |f| f.puts $report.join("\n") }
  WSApplication.message_box("Probe 2 complete.\n\n#{OUT_PATH}", "OK", "Information", false)
rescue => e
  say "Could not write: #{e.message}"
end
