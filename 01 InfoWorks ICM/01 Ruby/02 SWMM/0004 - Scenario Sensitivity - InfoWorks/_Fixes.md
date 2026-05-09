# Fixes for 0004 - Scenario Sensitivity - InfoWorks

Hardened `fix_*.rb` versions of each Ruby script in this folder. The originals
are preserved unchanged. The fixed versions add `# frozen_string_literal: true`,
explicit error handling with rollback on transactions, nil-safety on row
objects, and timestamped progress logging.

## fix_Scenario_GIM.rb

- **Purpose**: Build a parametric sweep of scenarios that scale
  `percolation_coefficient` on `hw_ground_infiltration` rows by
  `[-25%, -10%, +10%, +25%]`.
- **Hardening**:
  - `frozen_string_literal` pragma.
  - Validates `WSApplication.current_network` is not nil and the prompt was
    not cancelled.
  - `begin / rescue / ensure` around main loop.
  - `transaction_begin` paired with `transaction_rollback` on error.
  - `next if ro.nil?` and nil-checks on attributes.
  - Timestamped log helper.
- **How to run**: In InfoWorks ICM, open a network with
  `hw_ground_infiltration` rows, then run via `Network -> Run Ruby Script...`
  selecting `fix_Scenario_GIM.rb`.

## fix_Scenario_Link_Data.rb

- **Purpose**: Build a parametric sweep that scales `bottom_roughness_N`
  (Manning's n) on `hw_conduit` rows by `[-25%, -10%, +10%, +25%]` and reports
  total network roughness per scenario.
- **Hardening**:
  - `frozen_string_literal` pragma.
  - Network and prompt validation.
  - `begin / rescue / ensure` with rollback.
  - Nil-safe iteration.
  - Timestamped log helper.
- **How to run**: Open an InfoWorks ICM network with `hw_conduit` rows,
  then `Network -> Run Ruby Script...` and select `fix_Scenario_Link_Data.rb`.
