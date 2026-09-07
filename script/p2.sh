#!/bin/zsh
set -euo pipefail

root_dir="${0:A:h}/.."
mode="${1:-}"
run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
artifact_dir="${SYNORA_ARTIFACT_DIR:-${TMPDIR:-/private/tmp}/synora-wiki-p2-$run_id}"
scratch_dir="${SYNORA_P2_SCRATCH_DIR:-$artifact_dir/swiftpm}"
clang_cache="$artifact_dir/clang-module-cache"
swift_cache="$artifact_dir/swift-module-cache"
mkdir -p "$artifact_dir" "$clang_cache" "$swift_cache"

if [[ "$mode" != unit && "$mode" != integration && "$mode" != ui && "$mode" != recovery \
  && "$mode" != performance && "$mode" != visual && "$mode" != stage ]]; then
  print -u2 "usage: $0 {unit|integration|ui|recovery|performance|visual|stage}"
  exit 2
fi

export CLANG_MODULE_CACHE_PATH="$clang_cache"
export SWIFT_MODULECACHE_PATH="$swift_cache"
if [[ -n "${SYNORA_P2_GIT_CONFIG_GLOBAL:-}" ]]; then
  export GIT_CONFIG_GLOBAL="$SYNORA_P2_GIT_CONFIG_GLOBAL"
fi

spm_test() {
  local log_name="$1"
  shift
  swift test --disable-sandbox \
    --package-path "$root_dir/Packages/SynoraCore" \
    --scratch-path "$scratch_dir" \
    -Xswiftc -warnings-as-errors "$@" 2>&1 | tee "$artifact_dir/$log_name"
}

run_unit() {
  spm_test unit.log \
    --filter SynoraDomainTests \
    --filter SynoraEditorKitTests \
    --filter SynoraStoreTests \
    --filter SynoraAssetsTests \
    --filter SynoraExportTests
}

run_integration() {
  spm_test integration.log \
    --filter SynoraStoreTests \
    --filter SynoraAssetsTests \
    --filter SynoraExportTests
}

run_recovery() {
  local build_log="$artifact_dir/recovery-build.log"
  swift build --disable-sandbox \
    --package-path "$root_dir/Packages/SynoraCore" \
    --scratch-path "$scratch_dir" \
    --product SynoraP2Recovery \
    -Xswiftc -warnings-as-errors 2>&1 | tee "$build_log"
  local binary
  binary="$(find "$scratch_dir" -type f -name SynoraP2Recovery -perm -111 -print -quit)"
  [[ -n "$binary" ]] || { print -u2 "recovery writer binary not found"; return 1; }
  local database="$artifact_dir/recovery.sqlite"
  local writer_log="$artifact_dir/recovery-writer.log"
  "$binary" "$database" > "$writer_log" 2>&1 &
  local writer_pid=$!
  sleep "${SYNORA_P2_RECOVERY_DELAY:-1}"
  kill -KILL "$writer_pid" 2>/dev/null || true
  set +e
  wait "$writer_pid"
  local writer_exit=$?
  set -e
  "$binary" "$database" --check | tee "$artifact_dir/recovery-check.log"
  print "P2 recovery writer exit=$writer_exit; post-SIGKILL integrity check passed"
}

run_performance() {
  local output="$artifact_dir/performance"
  mkdir -p "$output"
  swift run --disable-sandbox \
    --package-path "$root_dir/Packages/SynoraCore" \
    --scratch-path "$scratch_dir" \
    SynoraP2Performance --output "$output" 2>&1 | tee "$artifact_dir/performance.log"
  [[ -s "$output/report.json" ]] || { print -u2 "performance report missing"; return 1; }
  cp "$output/report.json" "$artifact_dir/performance-report.json"
}

run_ui() {
  SYNORA_ARTIFACT_DIR="$artifact_dir/ui" "$root_dir/script/p1.sh" ui
}

run_visual() {
  SYNORA_ARTIFACT_DIR="$artifact_dir/visual" "$root_dir/script/p1.sh" visual
}

evidence_status() {
  local variable_name="$1"
  local path="${(P)variable_name:-}"
  [[ -n "$path" && -s "$path" ]] && print VERIFIED_EVIDENCE_FILE || print UNVERIFIED
}

run_stage() {
  run_unit
  run_integration
  run_recovery
  run_performance

  local ui_state="SKIPPED_UNVERIFIED"
  local visual_state="SKIPPED_UNVERIFIED"
  if [[ "${SYNORA_P2_RUN_UI:-0}" == "1" ]]; then
    run_ui
    ui_state="EXECUTED"
    run_visual
    visual_state="P1_SHELL_ONLY"
  fi
  local ime_state="$(evidence_status SYNORA_P2_IME_EVIDENCE)"
  local voiceover_state="$(evidence_status SYNORA_P2_VOICEOVER_EVIDENCE)"
  local paint_state="$(evidence_status SYNORA_P2_INSTRUMENTS_EVIDENCE)"
  cat > "$artifact_dir/stage-status.json" <<EOF
{
  "unit": "PASS",
  "integration": "PASS",
  "recovery": "PASS",
  "performance": "MODEL_ONLY",
  "ui": "$ui_state",
  "visual": "$visual_state",
  "realIME": "$ime_state",
  "realVoiceOver": "$voiceover_state",
  "keystrokeToPaint": "$paint_state",
  "stage": "CHANGES_REQUIRED"
}
EOF
  print "P2 stage status: CHANGES_REQUIRED (real IME/VoiceOver/keystroke-to-paint evidence is required)"
  print "artifacts: $artifact_dir"
  return 2
}

case "$mode" in
  unit) run_unit ;;
  integration) run_integration ;;
  ui) run_ui ;;
  recovery) run_recovery ;;
  performance) run_performance ;;
  visual) run_visual ;;
  stage) run_stage ;;
esac

print "P2 $mode checks complete: $artifact_dir"
