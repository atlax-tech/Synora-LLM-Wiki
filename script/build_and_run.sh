#!/bin/zsh
set -euo pipefail

root_dir="${0:A:h}/.."
configuration=Debug
verify=false
show_logs=false
show_telemetry=false
run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"

while (( $# > 0 )); do
  case "$1" in
    --debug) configuration=Debug ;;
    --release) configuration=Release ;;
    --verify) verify=true ;;
    --logs) show_logs=true ;;
    --telemetry) show_telemetry=true ;;
    *) print -u2 "unknown option: $1"; exit 2 ;;
  esac
  shift
done

artifact_dir="${SYNORA_ARTIFACT_DIR:-${TMPDIR:-/private/tmp}/synora-wiki-run-$run_id}"
derived_data="${SYNORA_DERIVED_DATA:-$artifact_dir/xcode}"
mkdir -p "$artifact_dir"

stop_existing() {
  local executable="$1"
  local pid
  while read -r pid; do
    [[ -n "$pid" ]] || continue
    kill "$pid" 2>/dev/null || true
  done < <(pgrep -f -- "$executable" || true)
  for _ in {1..20}; do
    pgrep -f -- "$executable" >/dev/null 2>&1 || return 0
    sleep 0.1
  done
  while read -r pid; do
    [[ -n "$pid" ]] || continue
    kill -9 "$pid" 2>/dev/null || true
  done < <(pgrep -f -- "$executable" || true)
}

app="$derived_data/Build/Products/$configuration/SynoraWiki.app"
binary="$app/Contents/MacOS/SynoraWiki"
stop_existing "$binary"

xcodebuild \
  -project "$root_dir/SynoraWiki.xcodeproj" \
  -scheme SynoraWiki \
  -configuration "$configuration" \
  -derivedDataPath "$derived_data" \
  build | tee "$artifact_dir/xcode-build.log"

[[ -x "$binary" ]] || { print -u2 "missing app executable: $binary"; exit 1; }

if $verify; then
  bundle_id=$(plutil -extract CFBundleIdentifier raw -o - "$app/Contents/Info.plist")
  [[ "$bundle_id" == "tech.atlax.SynoraWiki" ]] || {
    print -u2 "unexpected bundle identifier: $bundle_id"
    exit 1
  }
  print "verified $bundle_id ($configuration, arm64, macOS 26, run $run_id)"
else
  open -n "$app"
  print "launched $app (run $run_id)"
fi

if $show_logs; then
  log show --last 2m --style compact \
    --predicate 'processImagePath CONTAINS[c] "SynoraWiki"' \
    > "$artifact_dir/runtime.log" 2>&1 || true
  print "logs: $artifact_dir/runtime.log"
fi

if $show_telemetry; then
  log show --last 2m --style compact \
    --predicate 'subsystem == "tech.atlax.SynoraWiki"' \
    > "$artifact_dir/telemetry.log" 2>&1 || true
  print "telemetry: $artifact_dir/telemetry.log"
fi
