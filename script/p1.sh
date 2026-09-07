#!/bin/zsh
set -euo pipefail

root_dir="${0:A:h}/.."
mode="${1:-}"
run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
artifact_dir="${SYNORA_ARTIFACT_DIR:-/private/tmp/synora-wiki-p1-$run_id}"
derived_data="${SYNORA_DERIVED_DATA:-/private/tmp/synora-p2-active-cache/xcode}"
cache_root="${SYNORA_P2_CACHE_ROOT:-/private/tmp/synora-p2-active-cache}"
clang_cache="${CLANG_MODULE_CACHE_PATH:-$cache_root/clang-module-cache}"
swift_cache="${SWIFT_MODULECACHE_PATH:-$cache_root/swift-module-cache}"
source_packages="${SYNORA_CLONED_SOURCE_PACKAGES:-$derived_data/SourcePackages}"
mkdir -p "$artifact_dir"
mkdir -p "$derived_data" "$clang_cache" "$swift_cache" "$source_packages"

if [[ "$mode" != unit && "$mode" != ui && "$mode" != visual && "$mode" != stage ]]; then
  print -u2 "usage: $0 {unit|ui|visual|stage}"
  exit 2
fi

xcode_test() {
  local test_filter="$1"
  shift
  CLANG_MODULE_CACHE_PATH="$clang_cache" \
    SWIFT_MODULECACHE_PATH="$swift_cache" \
    xcodebuild -jobs 2 \
    -project "$root_dir/SynoraWiki.xcodeproj" \
    -scheme SynoraWiki \
    -configuration Debug \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$derived_data" \
    -clonedSourcePackagesDirPath "$source_packages" \
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
    xcode_test SynoraWikiUITests/SynoraWikiUITests/testCapturesSixShellCandidates \
      -resultBundlePath "$artifact_dir/visual.xcresult" \
    | tee "$artifact_dir/visual-capture.log"

  local result_bundle="$artifact_dir/visual.xcresult"
  [[ -d "$result_bundle" ]] || {
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
        if prefix in {
            "shell-light-compact",
            "shell-light-default",
            "shell-light-large",
            "shell-dark-compact",
            "shell-dark-default",
            "shell-dark-large",
        }:
            source = export_dir / attachment["exportedFileName"]
            target = candidates_dir / f"{prefix}.png"
            if not target.is_file():
                shutil.copyfile(source, target)

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
  if [[ "$mode" == stage ]]; then
    local stage_baseline="${SYNORA_VISUAL_BASELINE_DIR:-$root_dir/Tests/VisualBaselines/P1}"
    [[ -d "$stage_baseline" ]] || {
      print -u2 "stage baseline directory does not exist: $stage_baseline"
      exit 1
    }
    baseline_args+=(--baseline "$stage_baseline")
    baseline_args+=(--require-baseline)
    baseline_args+=(--allow-display-clamp)
  fi
  if [[ "$mode" != stage && -n "${SYNORA_VISUAL_BASELINE_DIR:-}" ]]; then
    baseline_args+=(--baseline "$SYNORA_VISUAL_BASELINE_DIR")
  fi
  python3 "$root_dir/script/p1_visual.py" \
    --candidates "$candidates" \
    --metadata "$candidates/visual-metadata.json" \
    --report "$artifact_dir/visual-report-light.json" \
    --theme light \
    "${baseline_args[@]}"
  python3 "$root_dir/script/p1_visual.py" \
    --candidates "$candidates" \
    --metadata "$candidates/visual-metadata.json" \
    --report "$artifact_dir/visual-report-dark.json" \
    --theme dark \
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
