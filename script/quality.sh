#!/bin/zsh
set -euo pipefail

root_dir="${0:A:h}/.."
artifact_dir="${SYNORA_ARTIFACT_DIR:-${TMPDIR:-/private/tmp}/synora-wiki-quality-$$}"
derived_data="$artifact_dir/xcode"
mkdir -p "$artifact_dir"
cd "$root_dir"

"$root_dir/script/bootstrap_wasmtime.sh"

if [[ "${SYNORA_XCODE_CONTAINER:-workspace}" == "project" ]]; then
  xcode_container=(-project "$root_dir/SynoraWiki.xcodeproj")
else
  xcode_container=(-workspace "$root_dir/SynoraWiki.xcworkspace")
fi

{
  xcodebuild -version
  swift --version
  xcrun swift-format --version
} | tee "$artifact_dir/tool-versions.txt"

git diff --check
xcrun swift-format lint --recursive --parallel --strict \
  App Packages/SynoraCore/Sources Packages/SynoraCore/Tests Tests

swift build --package-path Packages/SynoraCore --scratch-path "$artifact_dir/swiftpm-build"
swift test --package-path Packages/SynoraCore --scratch-path "$artifact_dir/swiftpm-test" \
  --skip SynoraStoreHeavyTests --enable-code-coverage | tee "$artifact_dir/swift-test.log"

profdata=$(find "$artifact_dir/swiftpm-test" -name default.profdata -print -quit)
test_binary=$(find "$artifact_dir/swiftpm-test" -path '*SynoraCorePackageTests.xctest/Contents/MacOS/SynoraCorePackageTests' -print -quit)
[[ -n "$profdata" && -n "$test_binary" ]]
xcrun llvm-cov report "$test_binary" -instr-profile "$profdata" \
  -ignore-filename-regex='GRDB\.swift|GRDB\.build|Tests/|runner\.swift' \
  | tee "$artifact_dir/swift-coverage.txt"
line_coverage=$(awk '/^TOTAL[[:space:]]/ { gsub(/%/, "", $10); print $10 }' "$artifact_dir/swift-coverage.txt")
[[ -n "$line_coverage" && "$line_coverage" != "-" ]]
awk -v coverage="$line_coverage" 'BEGIN { exit !(coverage >= 85) }'
branch_coverage=$(awk '/^TOTAL[[:space:]]/ { gsub(/%/, "", $13); print $13 }' "$artifact_dir/swift-coverage.txt")
if [[ "$branch_coverage" == "-" ]]; then
  print "coverage branches: unavailable in SwiftPM llvm-cov output" | tee "$artifact_dir/coverage-status.txt"
else
  awk -v coverage="$branch_coverage" 'BEGIN { exit !(coverage >= 75) }'
fi

for configuration in Debug Release; do
  xcodebuild \
    "${xcode_container[@]}" \
    -scheme SynoraWiki \
    -configuration "$configuration" \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$derived_data/$configuration" \
    CODE_SIGNING_ALLOWED=YES \
    build | tee "$artifact_dir/xcode-build-$configuration.log"
done

xcodebuild \
  "${xcode_container[@]}" \
  -scheme SynoraP0Probes \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$derived_data/Probes" \
  CODE_SIGNING_ALLOWED=YES \
  build | tee "$artifact_dir/xcode-build-probes.log"

# Register the probe host under a stable path so LaunchServices can resolve it.
probe_host_dir="$HOME/Library/Caches/SynoraProbeHost"
probe_host_app="$probe_host_dir/SynoraP0Probes.app"
mkdir -p "$probe_host_dir"
rm -rf "$probe_host_app"
cp -R "$derived_data/Probes/Build/Products/Debug/SynoraP0Probes.app" "$probe_host_app"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$lsregister" -f "$probe_host_app"

xcodebuild \
  "${xcode_container[@]}" \
  -scheme SynoraWiki \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$derived_data/Test" \
  -resultBundlePath "$artifact_dir/SynoraWiki.xcresult" \
  CODE_SIGNING_ALLOWED=YES \
  test | tee "$artifact_dir/xcode-test.log"

release_app="$derived_data/Release/Build/Products/Release/SynoraWiki.app"

# XPC + real guest end-to-end: launch the probe host and check its fixture report.
# The sandboxed app services are invisible to external processes, so the host runs
# the fixture itself and persists the outcome in its container temp directory.
fixture_report="$HOME/Library/Containers/tech.atlax.SynoraWiki.P0Probes/Data/tmp/synora-xpc-fixture.json"
rm -f "$fixture_report"
open "$probe_host_app"
fixture_ok=false
for _ in {1..30}; do
  if [[ -f "$fixture_report" ]] && grep -q '"status" *: *"success"' "$fixture_report"; then
    fixture_ok=true
    break
  fi
  sleep 1
done
for pid in $(pgrep -f "$probe_host_app" || true); do kill "$pid" 2>/dev/null || true; done
if [[ "$fixture_ok" != true ]]; then
  print -u2 "XPC guest fixture did not succeed: $(cat "$fixture_report" 2>/dev/null || echo 'no report')"
  exit 1
fi
print "xpc guest fixture succeeded: $(cat "$fixture_report")"

# Sentinel scan: planted test content and the reserved secret marker must never
# reach logs, xcresults, entitlements or the release bundle. Test sources embed the
# content sentinel by design, so build intermediates are not scanned.
sentinel_hits=$(
  {
    grep -rao -f <(printf 'SYNORA-SENTINEL-CONTENT-20260905\nSYNORA-SENTINEL-SECRET-20260905\n') \
      "$artifact_dir"/*.log "$artifact_dir"/SynoraWiki.xcresult \
      "$artifact_dir"/release-entitlements.plist "$fixture_report" 2>/dev/null || true
    log show --last 20m --style compact \
      --predicate 'processImagePath CONTAINS[c] "Synora"' 2>/dev/null \
      | grep -ao 'SYNORA-SENTINEL-\(CONTENT\|SECRET\)-20260905' || true
    grep -rao 'SYNORA-SENTINEL-\(CONTENT\|SECRET\)-20260905' "$release_app" 2>/dev/null || true
  } | sort -u
)
[[ -z "$sentinel_hits" ]] || {
  print -u2 "sentinel leak detected: $sentinel_hits"
  exit 1
}
print "sentinel scan clean"

codesign --verify --deep --strict "$release_app"
bundle_id=$(plutil -extract CFBundleIdentifier raw -o - "$release_app/Contents/Info.plist")
[[ "$bundle_id" == "tech.atlax.SynoraWiki" ]]

codesign -d --entitlements :- "$release_app" 2>/dev/null > "$artifact_dir/release-entitlements.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' \
  "$artifact_dir/release-entitlements.plist")" == "true" ]]
if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.cs.disable-library-validation' \
  "$artifact_dir/release-entitlements.plist" >/dev/null 2>&1; then
  print -u2 "product app must not disable library validation"
  exit 1
fi

git diff --check
print "quality gate passed: $artifact_dir"
