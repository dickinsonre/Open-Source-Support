# 0025 - Miscellaneous - Hardened Wrapper Notes

This folder is a sandbox / tutorial / demos collection. Some scripts hit
the ICM API; others are pure-Ruby demos with no ICM dependency. Every
`.rb` file gets a `fix_<original>.rb` wrapper that preserves behavior via
`Kernel#load` and adds:

- `# frozen_string_literal: true` pragma
- File-level header (purpose, inputs, outputs, UI/EX, hardening notes)
- `begin / rescue StandardError / rescue Interrupt / rescue SystemExit / ensure`
- `WSApplication` and `current_network` checks where the original needs them
- Timestamped wrapper-level progress logging on stdout

Behavior is preserved verbatim.

## fix_Bill_James_Similarity_Index.rb
Wraps the standalone HydraulicNetworkComparison class demo. No ICM needed.

## fix_ICM Ruby Tutorials.rb
Wraps the row-object / row-object-collection access tutorial.
Validates current_network.

## fix_Input Message Box.rb
Wraps the input_box demo. Validates WSApplication availability.

## fix_Sandbox.rb
Wraps the instance_eval demo. No ICM needed.

## fix_dave.rb
Wraps the appreciation ASCII-art print script. No ICM needed.

## fix_hub.rb
Wraps the InfoWorks ICM Technical Information Hub print-out. No ICM needed.

## fix_hw_parameters.rb
Wraps the hw_* parameter reference listing (comments-only file).

## fix_master_all_1.rb
Wraps the concatenated pipe-length-statistics scripts. Validates
current_network.

## fix_prompt_layout.rb
Wraps the multi-row WSApplication.prompt layout demo. Validates
current_network.

## fix_sw_parameters.rb
Wraps the sw_* parameter reference listing (comments-only file).

## fix_test_prompt_limit.rb
Wraps the prompt-row-count limit probe. Validates WSApplication.
