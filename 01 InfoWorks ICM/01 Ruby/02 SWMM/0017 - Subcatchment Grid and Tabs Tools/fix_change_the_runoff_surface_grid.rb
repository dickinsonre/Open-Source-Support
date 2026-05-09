# frozen_string_literal: true

# ============================================================================
# FIXED: Change the Runoff Surface Grid
# ============================================================================
# Purpose: Update runoff surface grid assignments for selected subcatchments;
#   prompt user for new grid ID or coordinates.
# Inputs: Network with selected subcatchments (sw_subcatchment or hw_subcatchment);
#   user input for new grid.
# Outputs: Modified subcatchment runoff_surface_grid fields; summary in console.
# Hardening:
#   - frozen_string_literal; begin/rescue/ensure
#   - Network nil-check
#   - Selection iteration with nil-safety
#   - Transaction begin/commit/rollback
#   - Row object nil-checks before field access
#   - Field write error handling (not crash)
#   - Progress logging every 10 subcatchments
#   - User prompt validation
# ============================================================================

begin
  net = WSApplication.current_network

  unless net
    WSApplication.message_box("ERROR: No network open", "OK", "!", false)
    exit
  end

  # Prompt user for new grid ID
  result = WSApplication.prompt(
    "Change Runoff Surface Grid for Selected Subcatchments",
    [
      ['New Runoff Surface Grid ID', 'String', '', nil],
      ['Confirm changes (dry run first)?', 'Boolean', false]
    ],
    false
  )

  if result.nil? || result.empty?
    puts "User cancelled"
    exit
  end

  new_grid_id = result[0].to_s.strip
  dry_run = result[1]

  if new_grid_id.empty?
    WSApplication.message_box("ERROR: Grid ID cannot be empty", "OK", "!", false)
    exit
  end

  puts "\n" + "="*80
  puts "CHANGE RUNOFF SURFACE GRID"
  puts "="*80
  puts "New Grid ID: #{new_grid_id}"
  puts "Dry Run: #{dry_run}"
  puts ""

  processed = 0
  updated = 0
  errors = 0
  skipped = 0

  unless dry_run
    begin
      net.transaction_begin
      puts "[OK] Transaction started"
    rescue => e
      puts "[!] Could not start transaction: #{e.message}"
      puts "[!] Continuing without transaction (changes may not be saved)"
    end
  end

  begin
    net.each_selected do |sel|
      begin
        next if sel.nil?

        # Try both hw_subcatchment and sw_subcatchment
        ro = nil
        begin
          ro = net.row_object('hw_subcatchment', sel.id)
        rescue
          ro = nil
        end

        unless ro
          begin
            ro = net.row_object('sw_subcatchment', sel.id)
          rescue
            ro = nil
          end
        end

        if ro.nil?
          skipped += 1
          next
        end

        processed += 1

        if processed % 10 == 0
          puts "Progress: #{processed} processed, #{updated} updated"
        end

        old_grid = ro.runoff_surface_grid rescue nil

        unless dry_run
          begin
            ro.runoff_surface_grid = new_grid_id
            ro.write
            updated += 1
            puts "  [OK] #{sel.id}: #{old_grid} -> #{new_grid_id}" if processed <= 20
          rescue => e
            errors += 1
            puts "  [X] #{sel.id}: #{e.message}"
            next
          end
        else
          updated += 1
          puts "  [DRY] #{sel.id}: #{old_grid} -> #{new_grid_id}" if processed <= 20
        end

      rescue => e
        errors += 1
        puts "ERROR processing #{sel&.id || 'unknown'}: #{e.message}"
        next
      end
    end

    unless dry_run
      begin
        net.transaction_commit
        puts "\n[OK] Transaction committed"
      rescue => e
        puts "\n[X] Error committing: #{e.message}"
      end
    else
      puts "\n[OK] Dry run complete - no changes made"
    end

  rescue => e
    puts "\n[X] FATAL ERROR: #{e.message}"
    unless dry_run
      begin
        net.transaction_rollback
      rescue
      end
    end
  end

  puts "\n" + "="*80
  puts "SUMMARY"
  puts "="*80
  puts "Processed: #{processed}"
  puts "Updated: #{updated}"
  puts "Skipped: #{skipped}"
  puts "Errors: #{errors}"
  puts "="*80

rescue => e
  puts "FATAL: #{e.message}"
  exit
end
