# ============================================================================
# Launcher for Probe 6 (UI script)
# ============================================================================
# Runs ICM_API_Probe6_Exchange.rb inside ICMExchange and streams its output.
#
# HOW TO USE:  Network > Run Ruby Script > this file
# ============================================================================

require 'open3'

PROBE = 'C:/temp/ICM_API_Probe6_Exchange.rb'

def find_icm_exchange
  known = [
    "C:\\Program Files\\Autodesk\\InfoWorks ICM Ultimate 2027\\ICMExchange.exe",
    "C:\\Program Files\\Autodesk\\InfoWorks ICM 2027\\ICMExchange.exe",
    "C:\\Program Files\\Autodesk\\InfoWorks ICM Ultimate 2026\\ICMExchange.exe",
    "C:\\Program Files\\Autodesk\\InfoWorks ICM 2026\\ICMExchange.exe"
  ]
  known.each { |p| return p if File.exist?(p) }
  ["Autodesk", "Innovyze"].each do |vendor|
    pf = ENV['ProgramFiles'] || "C:\\Program Files"
    hits = Dir.glob(File.join(pf, vendor, "InfoWorks ICM*", "ICMExchange.exe").gsub('\\', '/')).sort.reverse
    return hits.first if hits.any?
  end
  nil
end

unless File.exist?(PROBE)
  WSApplication.message_box("Probe script not found:\n#{PROBE}", "OK", "!", false)
  exit
end

exe = find_icm_exchange
if exe.nil?
  WSApplication.message_box("ICMExchange.exe not found.", "OK", "!", false)
  exit
end

puts "Launching: #{exe}"
puts "Probe    : #{PROBE}"
puts "=" * 70

begin
  Open3.popen2e("\"#{exe}\" \"#{PROBE}\" /ICM") do |_stdin, out, wait_thr|
    out.each { |line| puts line }
    puts "=" * 70
    puts "ICMExchange exit code: #{wait_thr.value.exitstatus}"
  end
rescue => e
  WSApplication.message_box("Failed to launch ICMExchange:\n\n#{e.message}", "OK", "!", false)
  exit
end

WSApplication.message_box(
  "Probe 6 finished.\n\nReport:\nC:\\temp\\ICM_API_Probe6.txt",
  "OK", "Information", false
)
