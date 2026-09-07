#!/bin/zsh
set -euo pipefail

root_dir="${0:A:h}/.."
mode="${1:-}"
run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
artifact_dir="${SYNORA_ARTIFACT_DIR:-/private/tmp/synora-wiki-p2-$run_id}"
cache_root="${SYNORA_P2_CACHE_ROOT:-/private/tmp/synora-p2-active-cache}"
scratch_dir="${SYNORA_P2_SCRATCH_DIR:-$cache_root/swiftpm}"
export SYNORA_DERIVED_DATA="${SYNORA_DERIVED_DATA:-$cache_root/xcode}"
export SYNORA_P2_CACHE_ROOT="$cache_root"
clang_cache="$cache_root/clang-module-cache"
swift_cache="$cache_root/swift-module-cache"
# Own one heavy job and its children; stage remains a read-only aggregation.
if [[ "$mode" != stage && "${SYNORA_P2_RESOURCE_OWNER:-}" != "owned" ]]; then
  export SYNORA_P2_RESOURCE_OWNER=child
  python3 - "$0" "$mode" "$cache_root" "$artifact_dir" <<'PY_RESOURCE'
import os, shutil, signal, subprocess, sys, time
from pathlib import Path
script, mode, cache, artifacts = sys.argv[1:]
lock = Path(cache + ".lock")
try:
    lock.mkdir()
except FileExistsError:
    raise SystemExit("P2 resource lock exists; inspect its owner before retrying: " + str(lock))
child = None
code = 1
try:
    (lock / "pid").write_text(str(os.getpid()))
    if shutil.disk_usage('/System/Volumes/Data').free < 30 * 2**30:
        raise RuntimeError("less than 30 GiB free; clean test artifacts first")
    env = dict(os.environ, SYNORA_P2_RESOURCE_OWNER="owned")
    child = subprocess.Popen(['zsh', script, mode], env=env, start_new_session=True)
    def interrupted(signum, frame):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, interrupted)
    while child.poll() is None:
        time.sleep(5)
        total = 0
        for directory in {cache, artifacts}:
            if Path(directory).exists():
                result = subprocess.check_output(['du', '-sk', directory], text=True)
                total += int(result.split()[0]) * 1024
        if total > 10 * 2**30 or shutil.disk_usage('/System/Volumes/Data').free < 30 * 2**30:
            raise RuntimeError("P2 temporary disk budget exceeded")
    code = child.returncode
except (RuntimeError, KeyboardInterrupt) as error:
    print(str(error) or "P2 interrupted", file=sys.stderr)
finally:
    if child is not None:
        try:
            os.killpg(child.pid, signal.SIGTERM)
            time.sleep(1)
            os.killpg(child.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        child.wait()
    # Preserve reports; remove only this script's reproducible fixtures/cache.
    for name in ('recovery.sqlite', 'recovery.sqlite-wal', 'recovery.sqlite-shm'):
        (Path(artifacts) / name).unlink(missing_ok=True)
    shutil.rmtree(Path(artifacts) / 'performance', ignore_errors=True)
    logs = Path(cache) / 'xcode' / 'Logs'
    if logs.is_dir():
        destination = Path(artifacts) / 'xcode-logs'
        destination.parent.mkdir(parents=True, exist_ok=True)
        if not destination.exists():
            shutil.move(str(logs), str(destination))
    if os.environ.get('SYNORA_P2_KEEP_CACHE') != '1':
        shutil.rmtree(cache, ignore_errors=True)
    shutil.rmtree(lock)
sys.exit(code)
PY_RESOURCE
  exit $?
fi
mkdir -p "$artifact_dir"
if [[ "$mode" != stage ]]; then
  mkdir -p "$clang_cache" "$swift_cache"
fi

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
  swift test --jobs 2 --disable-sandbox \
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
  swift build --jobs 2 --disable-sandbox \
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
  swift run --jobs 2 --disable-sandbox \
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

# stage consumes existing evidence; it never launches builds or Instruments.
# SYNORA_P2_STAGE_EVIDENCE points to JSON with schemaVersion=1, sourceSHA,
# trackedDiffSHA256 (SHA256 of git diff HEAD --binary), configuration,
# environment (nonempty object), and checks keyed by the names below.
# Each check has status="PASS" and artifacts=[paths relative to the manifest].
# keystrokeToPaint also has modelOnly=false, realWindow=true, textLength>=100000,
# mediaCount>=200, and rounds (>=3), each containing raw nonnegative millisecond
# arrays inputMs (>=100) and firstScreenMs (>=30). Samples must not be filtered.
run_stage() {
  python3 - "$root_dir" "$artifact_dir" <<'PY_STAGE'
import hashlib
import json
import math
import os
from pathlib import Path
import subprocess
import sys

root, output = map(Path, sys.argv[1:])
required = ("unit", "integration", "app", "ui", "blocks", "media", "export",
            "recovery", "realIME", "realVoiceOver", "keystrokeToPaint", "visual")
report = {"stage": "ERROR", "checks": {}, "reasons": []}

def reject(message):
    report["reasons"].append(message)

def percentile(values, fraction):
    return sorted(values)[math.ceil(len(values) * fraction) - 1]

try:
    sha = subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()
    diff = subprocess.check_output(["git", "-C", str(root), "diff", "HEAD", "--binary"])
    fingerprint = hashlib.sha256(diff).hexdigest()
    report.update(sourceSHA=sha, trackedDiffSHA256=fingerprint)
    manifest = os.environ.get("SYNORA_P2_STAGE_EVIDENCE", "")
    evidence = {}
    base = root
    if not manifest:
        reject("SYNORA_P2_STAGE_EVIDENCE is missing")
    else:
        base = Path(manifest).resolve().parent
        try:
            evidence = json.loads(Path(manifest).read_text())
            if not isinstance(evidence, dict):
                raise ValueError("expected JSON object")
        except (OSError, ValueError) as error:
            reject("invalid evidence: " + str(error))
            evidence = {}
    if evidence.get("schemaVersion") != 1:
        reject("schemaVersion must be 1")
    if evidence.get("sourceSHA") != sha or evidence.get("trackedDiffSHA256") != fingerprint:
        reject("evidence does not match current HEAD and tracked working tree")
    if not isinstance(evidence.get("configuration"), str) or not evidence["configuration"].strip():
        reject("configuration is missing")
    if not isinstance(evidence.get("environment"), dict) or not evidence["environment"]:
        reject("environment is missing")
    checks = evidence.get("checks", {})
    if not isinstance(checks, dict):
        checks = {}
    for name in required:
        start = len(report["reasons"])
        check = checks.get(name, {})
        if not isinstance(check, dict):
            check = {}
        if check.get("status") != "PASS":
            reject(name + ": missing or not PASS")
        artifacts = check.get("artifacts")
        if not isinstance(artifacts, list) or not artifacts:
            reject(name + ": raw artifacts missing")
        else:
            for artifact in artifacts:
                if not isinstance(artifact, str) or not artifact:
                    reject(name + ": invalid artifact path")
                    continue
                path = base / artifact
                if not path.is_file() or path.stat().st_size == 0:
                    reject(name + ": missing or empty artifact " + artifact)
        if name == "keystrokeToPaint":
            if check.get("modelOnly") is not False or check.get("realWindow") is not True:
                reject(name + ": real window evidence required; model timings are insufficient")
            for key, minimum in (("textLength", 100000), ("mediaCount", 200)):
                value = check.get(key)
                if type(value) is not int or value < minimum:
                    reject(name + ": insufficient " + key)
            rounds = check.get("rounds")
            if not isinstance(rounds, list) or len(rounds) < 3:
                reject(name + ": at least three rounds required")
            if isinstance(rounds, list):
                for index, run in enumerate(rounds):
                    for key, minimum, limits in (("inputMs", 100, ((.95, 16), (.99, 32))),
                                                  ("firstScreenMs", 30, ((.95, 250),))):
                        values = run.get(key) if isinstance(run, dict) else None
                        if (not isinstance(values, list) or len(values) < minimum or
                            any(type(v) not in (int, float) or not math.isfinite(v) or v < 0 for v in values)):
                            reject(f"{name}: round {index + 1} invalid or insufficient {key}")
                            continue
                        for fraction, limit in limits:
                            if percentile(values, fraction) > limit:
                                reject(f"{name}: round {index + 1} {key} P{fraction * 100:g} exceeds {limit} ms")
        report["checks"][name] = "PASS" if len(report["reasons"]) == start else "CHANGES_REQUIRED"
    report["stage"] = "CHANGES_REQUIRED" if report["reasons"] else "PASS"
except Exception as error:
    report["stage"] = "ERROR"
    reject("validator error: " + str(error))

(output / "stage-status.json").write_text(json.dumps(report, indent=2) + "\n")
print("P2 stage status: " + report["stage"])
for reason in report["reasons"]:
    print("- " + reason)
print("report: " + str(output / "stage-status.json"))
sys.exit({"PASS": 0, "CHANGES_REQUIRED": 2, "ERROR": 1}[report["stage"]])
PY_STAGE
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
