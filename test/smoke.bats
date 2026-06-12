#!/usr/bin/env bats
#
# Platform-agnostic smoke tests — exercise arg handling that runs before any
# Apple-Silicon / MLX preflight, so they pass on Linux CI runners too.

BIN="${BATS_TEST_DIRNAME}/../bin/localreview"

@test "--help exits 0 and shows usage" {
  run "$BIN" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: localreview"* ]]
}

@test "--version prints the version" {
  run "$BIN" --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"localreview 0.2.0"* ]]
}

@test "unknown option fails with a message" {
  run "$BIN" --nope
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown option"* ]]
}

@test "--comment without --pr is rejected" {
  run "$BIN" --comment
  [ "$status" -ne 0 ]
  [[ "$output" == *"requires --pr"* ]]
}
