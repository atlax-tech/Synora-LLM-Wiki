#!/bin/zsh
set -euo pipefail

version="48.0.1"
asset="wasmtime-v${version}-aarch64-macos-c-api.tar.xz"
url="https://github.com/bytecodealliance/wasmtime/releases/download/v${version}/${asset}"
sha256="9e3c636ed487a41026ff76388c5fa6f3a48ea0968408d033ed4b5e8082c20d69"
root_dir="${0:A:h}/.."
vendor_dir="${SYNORA_WASMTIME_DIR:-$root_dir/.build/vendor/wasmtime/v$version}"
archive="$vendor_dir/$asset"

mkdir -p "$vendor_dir"
if [[ ! -f "$archive" ]]; then
  curl --fail --location --proto '=https' --tlsv1.2 "$url" --output "$archive"
fi
actual=$(shasum -a 256 "$archive" | awk '{print $1}')
[[ "$actual" == "$sha256" ]] || {
  print -u2 "Wasmtime checksum mismatch: expected $sha256, got $actual"
  exit 1
}

extract_dir="$vendor_dir/extracted"
marker="$extract_dir/.verified-$sha256"
if [[ ! -f "$marker" || ! -f "$extract_dir/include/wasmtime.h" || \
  ! -f "$extract_dir/lib/libwasmtime.dylib" || ! -f "$extract_dir/lib/libwasmtime.a" || \
  ! -f "$extract_dir/LICENSE" ]]; then
  mkdir -p "$extract_dir"
  tar -xJf "$archive" --strip-components=1 -C "$extract_dir"
  [[ -f "$extract_dir/include/wasmtime.h" && -f "$extract_dir/lib/libwasmtime.dylib" && \
    -f "$extract_dir/lib/libwasmtime.a" && -f "$extract_dir/LICENSE" ]] || {
    print -u2 "Wasmtime archive is missing the expected C API files"
    exit 1
  }
  print -r -- "$sha256" > "$marker.tmp"
  mv -f "$marker.tmp" "$marker"
fi

print "Wasmtime $version verified: $extract_dir"
