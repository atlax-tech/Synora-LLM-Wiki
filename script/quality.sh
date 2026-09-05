#!/bin/zsh
set -euo pipefail

root_dir="${0:A:h}/.."
artifact_dir="${SYNORA_ARTIFACT_DIR:-${TMPDIR:-/private/tmp}/synora-wiki-quality-$$}"
derived_data="$artifact_dir/xcode"
mkdir -p "$artifact_dir"
cd "$root_dir"

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
  --enable-code-coverage | tee "$artifact_dir/swift-test.log"

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
  -scheme SynoraWiki \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$derived_data/Test" \
  -resultBundlePath "$artifact_dir/SynoraWiki.xcresult" \
  CODE_SIGNING_ALLOWED=YES \
  test | tee "$artifact_dir/xcode-test.log"

release_app="$derived_data/Release/Build/Products/Release/SynoraWiki.app"
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
