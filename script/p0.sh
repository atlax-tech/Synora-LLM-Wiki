#!/bin/zsh
set -euo pipefail

root_dir="${0:A:h}/.."
derived_data="${SYNORA_DERIVED_DATA:-/private/tmp/synora-wiki-derived-data}"
scratch_path="${SYNORA_SPM_SCRATCH:-/private/tmp/synora-wiki-spm}"

usage() {
  print "usage: $0 textkit|store|skill|benchmark|all"
}

run_textkit() {
  "$root_dir/script/bootstrap_wasmtime.sh"
  xcodebuild -project "$root_dir/SynoraWiki.xcodeproj" -scheme SynoraP0Probes \
    -configuration Debug -derivedDataPath "$derived_data/p0-probes" \
    CODE_SIGNING_ALLOWED=YES build
}

run_store() {
  swift test --package-path "$root_dir/Packages/SynoraCore" \
    --scratch-path "$scratch_path" --filter SynoraStoreProbeTests
}

run_skill() {
  "$root_dir/script/bootstrap_wasmtime.sh"
  local wasmtime_dir="${SYNORA_WASMTIME_DIR:-$root_dir/.build/vendor/wasmtime/v48.0.1}"
  export SYNORA_WASMTIME_ROOT="$wasmtime_dir/extracted"
  swift test --package-path "$root_dir/Packages/SynoraCore" \
    --scratch-path "$scratch_path" --filter SynoraSkillProbeTests
}

run_benchmark() {
  local output="${SYNORA_BENCHMARK_DIR:-/private/tmp/synora-wiki-benchmark-smoke}"
  local second_output="${output}.second"
  rm -rf "$output" "$second_output"
  swift run --package-path "$root_dir/Packages/SynoraCore" \
    --scratch-path "$scratch_path" SynoraBenchmarkGenerator \
    --profile smoke --seed 20260905 --output "$output" >/dev/null
  swift run --package-path "$root_dir/Packages/SynoraCore" \
    --scratch-path "$scratch_path" SynoraBenchmarkGenerator \
    --profile smoke --seed 20260905 --output "$second_output" >/dev/null
  for file in manifest.json records.jsonl blocks.jsonl assets/payload.tiff; do
    cmp "$output/$file" "$second_output/$file"
  done
  local first_hash
  first_hash=$(shasum -a 256 "$output/manifest.json" | awk '{print $1}')
  swift run --package-path "$root_dir/Packages/SynoraCore" \
    --scratch-path "$scratch_path" SynoraBenchmarkGenerator \
    --profile smoke --seed 20260905 --output "$output" --resume >/dev/null
  [[ "$first_hash" == "$(shasum -a 256 "$output/manifest.json" | awk '{print $1}')" ]]
  rm -rf "$second_output"
  print "benchmark smoke verified: $output"
}

case "${1:-}" in
  textkit) run_textkit ;;
  store) run_store ;;
  skill) run_skill ;;
  benchmark) run_benchmark ;;
  all) run_textkit; run_store; run_skill; run_benchmark ;;
  *) usage; exit 2 ;;
esac
