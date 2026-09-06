#!/bin/zsh
set -euo pipefail

root_dir="${0:A:h}/.."
mode="${1:-}"
run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
artifact_dir="${SYNORA_ARTIFACT_DIR:-${TMPDIR:-/private/tmp}/synora-wiki-p1-$run_id}"
derived_data="$artifact_dir/xcode"
mkdir -p "$artifact_dir"

if [[ "$mode" != unit && "$mode" != ui && "$mode" != visual && "$mode" != stage ]]; then
  print -u2 "usage: $0 {unit|ui|visual|stage}"
  exit 2
fi

xcode_test() {
  local test_filter="$1"
  shift
  xcodebuild \
    -project "$root_dir/SynoraWiki.xcodeproj" \
    -scheme SynoraWiki \
    -configuration Debug \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$derived_data" \
    "-only-testing:$test_filter" \
    test \
    "$@"
}

run_unit() {
  xcode_test SynoraWikiTests | tee "$artifact_dir/unit.log"
}

run_ui() {
  xcode_test SynoraWikiUITests | tee "$artifact_dir/ui.log"
}

run_visual() {
  local candidates="$artifact_dir/candidates"
  mkdir -p "$candidates"
  SYNORA_VISUAL_OUTPUT_DIR="$candidates" \
    xcode_test SynoraWikiUITests/SynoraWikiUITests/testCapturesThreeShellCandidates \
    | tee "$artifact_dir/visual-capture.log"

  local result_bundle
  result_bundle="$(find "$derived_data/Logs/Test" -maxdepth 1 -name '*.xcresult' -print -quit)"
  [[ -n "$result_bundle" ]] || {
    print -u2 "visual test did not produce an xcresult bundle"
    exit 1
  }
  local export_dir="$artifact_dir/exported-attachments"
  mkdir -p "$export_dir"
  xcrun xcresulttool export attachments \
    --path "$result_bundle" \
    --output-path "$export_dir"
  python3 - "$export_dir/manifest.json" "$export_dir" "$candidates" \
    "$artifact_dir/visual-capture.log" <<'PY'
import base64
import json
import shutil
import sys
from pathlib import Path

manifest_path, export_dir, candidates_dir, log_path = map(Path, sys.argv[1:])
manifest = json.loads(manifest_path.read_text())
for test in manifest:
    for attachment in test.get("attachments", []):
        suggested = attachment.get("suggestedHumanReadableName", "")
        prefix = suggested.split("_0_", 1)[0]
        if prefix in {"shell-compact", "shell-default", "shell-large"}:
            source = export_dir / attachment["exportedFileName"]
            shutil.copyfile(source, candidates_dir / f"{prefix}.png")

metadata_lines = [
    line.split("=", 1)[1].strip()
    for line in log_path.read_text().splitlines()
    if line.startswith("VISUAL_METADATA_BASE64=")
]
if not metadata_lines:
    raise SystemExit("visual test did not emit metadata")
metadata = base64.b64decode(metadata_lines[-1])
(candidates_dir / "visual-metadata.json").write_bytes(metadata)
PY

  local baseline_args=()
  if [[ -n "${SYNORA_VISUAL_BASELINE_DIR:-}" ]]; then
    baseline_args+=(--baseline "$SYNORA_VISUAL_BASELINE_DIR")
  fi
  python3 "$root_dir/script/p1_visual.py" \
    --candidates "$candidates" \
    --metadata "$candidates/visual-metadata.json" \
    --report "$artifact_dir/visual-report.json" \
    "${baseline_args[@]}"
}

case "$mode" in
  unit)
    run_unit
    ;;
  ui)
    run_ui
    ;;
  visual)
    run_visual
    ;;
  stage)
    run_unit
    run_ui
    run_visual
    ;;
esac

print "P1 $mode checks complete: $artifact_dir"
