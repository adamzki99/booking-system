#!/usr/bin/env bash
# go-test-report.sh - gate and summarize `go test -json` output.
#
# Usage:
#   go-test-report.sh <go-test-json-file> [--require-package <name>]...
#
# Reads newline-delimited JSON from `go test -json`. Lines that are not JSON
# are ignored: go test writes plain-text build errors into the same stream.
# Exits 1 when a test reported "skip" (a package-level skip event has no Test
# field and is allowed) or when a required package has zero passing tests.
# Prints a per-package markdown table to stdout and appends it to
# GITHUB_STEP_SUMMARY when that variable is set.
set -euo pipefail

usage() {
  echo "Usage: $0 <go-test-json-file> [--require-package <name>]..." >&2
}

json_file=""
required=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --require-package)
      if [[ $# -lt 2 ]]; then
        echo "ERROR: --require-package requires a package name" >&2
        usage
        exit 2
      fi
      required+=("$2")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "ERROR: unknown option: $1" >&2
      usage
      exit 2
      ;;
    *)
      if [[ -n "$json_file" ]]; then
        echo "ERROR: only one JSONL file may be given" >&2
        usage
        exit 2
      fi
      json_file="$1"
      shift
      ;;
  esac
done

if [[ -z "$json_file" || ! -f "$json_file" ]]; then
  echo "ERROR: JSONL file not found: ${json_file:-<none>}" >&2
  usage
  exit 2
fi

python3 - "$json_file" "${GITHUB_STEP_SUMMARY:-}" "${required[@]}" <<'PY'
import json
import sys
from collections import defaultdict

path, summary_path = sys.argv[1], sys.argv[2]
required = sys.argv[3:]

counts = defaultdict(lambda: {"pass": 0, "fail": 0, "skip": 0})
test_output = defaultdict(list)
package_output = defaultdict(list)
skipped = []
failed = []

with open(path, "r", encoding="utf-8", errors="replace") as stream:
    for line in stream:
        try:
            event = json.loads(line)
        except (ValueError, TypeError):
            continue
        if not isinstance(event, dict):
            continue

        action = event.get("Action")
        test = event.get("Test")
        package = event.get("Package", "")
        output = event.get("Output", "").rstrip("\n")

        if action == "output":
            if test:
                test_output[(package, test)].append(output)
            else:
                package_output[package].append(output)

        # A package-level skip (no Test) means "no test files"; only test-level
        # skip events are forbidden.
        if not test or action not in ("pass", "fail", "skip"):
            continue

        counts[package][action] += 1
        key = (package, test)
        if action == "skip":
            skipped.append((package, test, list(test_output[key])))
        elif action == "fail":
            failed.append((package, test, list(test_output[key])))

table = ["## Go test report", "", "| package | passed | failed | skipped |",
         "| --- | --- | --- | --- |"]
for package in sorted(counts):
    c = counts[package]
    table.append(f"| {package} | {c['pass']} | {c['fail']} | {c['skip']} |")
report = "\n".join(table) + "\n"
sys.stdout.write(report)
if summary_path:
    with open(summary_path, "a", encoding="utf-8") as summary:
        summary.write("\n" + report)

# Always surface failing-test output and race warnings: with `go test -json`
# redirected to a file, the raw stream is not readable in the job log.
if failed:
    print("ERROR: failing tests detected:", file=sys.stderr)
    for package, test, output in failed:
        print(f"  - {test} ({package})", file=sys.stderr)
        for line in output:
            print(f"      {line}", file=sys.stderr)
for package, lines in package_output.items():
    for line in lines:
        if "DATA RACE" in line:
            print(f"ERROR: data race detected: {line}", file=sys.stderr)

blocking = 0
if skipped:
    print("ERROR: skipped tests are not allowed:", file=sys.stderr)
    for package, test, output in skipped:
        print(f"  - {test} ({package})", file=sys.stderr)
        for line in output:
            print(f"      {line}", file=sys.stderr)
    blocking += 1

missing = [name for name in required
           if not any((package == name or package.endswith("/" + name))
                      and counts[package]["pass"] > 0 for package in counts)]
if missing:
    print("ERROR: required packages reported zero passing tests:", file=sys.stderr)
    for name in missing:
        print(f"  - {name}", file=sys.stderr)
    blocking += 1

sys.exit(1 if blocking else 0)
PY
