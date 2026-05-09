# frozen_string_literal: true
# ---------------------------------------------------------------------------
# fix_UI-UpdateFromExternalCSV.rb
#
# Purpose : Read an external CSV, build a per-key best-value lookup, then
#           update cams_manhole.user_text_2 in the current network from the
#           lookup keyed by user_text_1.
# Inputs  : test.csv next to script; current_network with cams_manhole rows.
# Outputs : Updated user_text_2 on matching cams_manhole rows.
# Type    : UI script.
# Hardening:
#   * frozen_string_literal pragma
#   * Validates current_network not nil
#   * Validates input csv exists
#   * Wraps transaction with rollback on error
#   * Nil-safety on lookups
#   * Timestamped logging
# ---------------------------------------------------------------------------

require 'csv'

def log(msg); puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] #{msg}"; end

begin
  script_dir = File.dirname(WSApplication.script_file)
  csv_path = File.join(script_dir, 'test.csv')
  raise "Input CSV not found: #{csv_path}" unless File.exist?(csv_path)

  my_hash = {}
  first = true
  File.open(csv_path) do |f|
    f.each_line do |l|
      if first
        first = false
        next
      end
      l.chomp!
      arr = CSV.parse_line(l)
      next if arr.nil? || arr[0].nil?
      key = arr[0]
      my_hash[key] ||= [nil, nil]
      if my_hash[key][0].nil? || (arr[2] && arr[2] > my_hash[key][0])
        my_hash[key][0] = arr[0]
        my_hash[key][1] = arr[1]
      end
    end
  end

  db = WSApplication.current_network
  raise 'No current network is open.' if db.nil?

  in_transaction = false
  begin
    db.transaction_begin
    in_transaction = true

    db.row_objects('cams_manhole').each do |v|
      next if v.nil?
      next unless my_hash.key?(v.user_text_1)
      val = my_hash.values_at(v.user_text_1)
      puts val[0].to_s
      v.user_text_2 = val[0][1].to_s
      v.write
    end

    db.transaction_commit
    in_transaction = false
  rescue StandardError => txn_err
    log "Transaction error: #{txn_err.message}"
    if in_transaction
      begin
        db.transaction_rollback
      rescue StandardError
        # ignore
      end
    end
    raise
  end
rescue StandardError => e
  log "Aborted: #{e.message}"
ensure
  log 'fix_UI-UpdateFromExternalCSV.rb finished.'
end
