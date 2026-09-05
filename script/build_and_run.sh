#!/bin/zsh
set -euo pipefail

root_dir="${0:A:h}/.."
configuration=Debug
verify=false

while (( $# > 0 )); do
  case "$1" in
    --debug) configuration=Debug ;;
    --release) configuration=Release ;;
    --verify) verify=true ;;
    *) print -u2 "unknown option: $1"; exit 2 ;;
  esac
  shift
done

derived_data="${SYNORA_DERIVED_DATA:-/private/tmp/synora-wiki-derived-data}"
xcodebuild \
  -project "$root_dir/SynoraWiki.xcodeproj" \
  -scheme SynoraWiki \
  -configuration "$configuration" \
  -derivedDataPath "$derived_data" \
  build

app="$derived_data/Build/Products/$configuration/SynoraWiki.app"
binary="$app/Contents/MacOS/SynoraWiki"
[[ -x "$binary" ]] || { print -u2 "missing app executable: $binary"; exit 1; }

if $verify; then
  bundle_id=$(plutil -extract CFBundleIdentifier raw -o - "$app/Contents/Info.plist")
  [[ "$bundle_id" == "tech.atlax.SynoraWiki" ]] || {
    print -u2 "unexpected bundle identifier: $bundle_id"
    exit 1
  }
  print "verified $bundle_id ($configuration, arm64, macOS 26)"
else
  open "$app"
fi
