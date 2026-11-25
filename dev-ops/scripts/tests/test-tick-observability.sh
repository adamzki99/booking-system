#!/usr/bin/env bash
# Observability regressions for lock skips and event-write failures.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
TICK="$REPO_ROOT/dev-ops/factory/tick.sh"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/factory-observability.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

git_bin="$(command -v git)"
real_python="$(command -v python3)"
export REAL_PYTHON="$real_python"
"$git_bin" init -q --bare "$tmp/repo.git"

stubs="$tmp/bin"
mkdir -p "$stubs" "$tmp/metrics" "$tmp/sessions" "$tmp/claims"
cat > "$stubs/gh" <<'EOF'
#!/usr/bin/env bash
case " $* " in
  *" repo view "*) printf 'owner/repo\n' ;;
  *) printf '[]\n' ;;
esac
EOF
cat > "$stubs/opencode" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then printf 'test\n'; fi
EOF
cat > "$stubs/python3" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == */dev-ops/factory/lib/factory.py && "${2:-}" == "emit" && "${3:-}" == "${FACTORY_EMIT_FAIL_EVENT:-}" && -n "${FACTORY_EMIT_FAIL_EVENT:-}" ]]; then
  exit 1
fi
exec "$REAL_PYTHON" "$@"
EOF
chmod +x "$stubs/gh" "$stubs/opencode" "$stubs/python3"

# A lock-skipped invocation must not race the active tick by rewriting metrics.
previous_timestamp=1234567890
cat > "$tmp/metrics/factory_tick.prom" <<EOF
# HELP factory_tick_last_run_timestamp_seconds Unix time of the last tick run.
# TYPE factory_tick_last_run_timestamp_seconds gauge
factory_tick_last_run_timestamp_seconds $previous_timestamp
# HELP factory_tick_last_success_timestamp_seconds Unix time of the last successful tick.
# TYPE factory_tick_last_success_timestamp_seconds gauge
factory_tick_last_success_timestamp_seconds $previous_timestamp
# HELP factory_tick_last_exit_code Exit code of the last tick.
# TYPE factory_tick_last_exit_code gauge
factory_tick_last_exit_code 0
EOF
cp "$tmp/metrics/factory_tick.prom" "$tmp/metrics.before"

lock_file="$tmp/repo.git/factory-tick.lock"
exec 8>"$lock_file"
flock -n 8

set +e
PATH="$stubs:$PATH" \
  GIT_DIR="$tmp/repo.git" \
  PYTHONDONTWRITEBYTECODE=1 \
  FACTORY_LOG_FILE="$tmp/tick.jsonl" \
  FACTORY_METRICS_DIR="$tmp/metrics" \
  FACTORY_SESSION_LOG_DIR="$tmp/sessions" \
  FACTORY_CLAIM_DIR="$tmp/claims" \
  bash "$TICK" --dry-run >"$tmp/lock-stdout" 2>"$tmp/lock-stderr"
rc=$?
set -e

flock -u 8
exec 8>&-

if [[ "$rc" -ne 0 ]]; then
  printf 'FAIL: lock-skipped tick exited %s\n' "$rc" >&2
  cat "$tmp/lock-stderr" >&2
  exit 1
fi
if ! grep -q '"event": "lock_skipped"' "$tmp/tick.jsonl"; then
  printf 'FAIL: lock_skipped event missing\n' >&2
  exit 1
fi
if ! cmp -s "$tmp/metrics.before" "$tmp/metrics/factory_tick.prom"; then
  printf 'FAIL: lock skip rewrote the active tick metrics\n' >&2
  diff -u "$tmp/metrics.before" "$tmp/metrics/factory_tick.prom" >&2 || true
  exit 1
fi
printf 'PASS: lock skip leaves active tick metrics unchanged\n'

# Run the current tick from an isolated clone so the emitter failure is tested
# through tick.sh without touching the real repository or starting sessions.
"$git_bin" clone -q --no-checkout "$REPO_ROOT" "$tmp/tick-repo"
"$git_bin" -C "$tmp/tick-repo" checkout -q "$("$git_bin" -C "$REPO_ROOT" rev-parse HEAD)"
cp "$TICK" "$tmp/tick-repo/dev-ops/factory/tick.sh"
cp "$REPO_ROOT/dev-ops/factory/lib/factory.py" "$tmp/tick-repo/dev-ops/factory/lib/factory.py"
"$git_bin" -C "$tmp/tick-repo" add dev-ops/factory/tick.sh dev-ops/factory/lib/factory.py
if ! "$git_bin" -C "$tmp/tick-repo" diff --cached --quiet -- dev-ops/factory/tick.sh dev-ops/factory/lib/factory.py; then
  "$git_bin" -C "$tmp/tick-repo" -c user.email=test@example.invalid -c user.name=test commit -qm "test tick/factory"
fi
"$git_bin" -C "$tmp/tick-repo" branch --no-track -f main HEAD
python3 "$tmp/tick-repo/dev-ops/factory/lib/factory.py" guardrail-manifest "$tmp/tick-repo" HEAD > "$tmp/guardrail-manifest.json"
"$git_bin" -C "$tmp/tick-repo" checkout -q -B factory-guardrail-approved HEAD
cp "$tmp/guardrail-manifest.json" "$tmp/tick-repo/guardrail-manifest.json"
"$git_bin" -C "$tmp/tick-repo" add guardrail-manifest.json
if ! "$git_bin" -C "$tmp/tick-repo" diff --cached --quiet -- guardrail-manifest.json; then
  "$git_bin" -C "$tmp/tick-repo" -c user.email=test@example.invalid -c user.name=test commit -qm "guardrail manifest"
fi
"$git_bin" -C "$tmp/tick-repo" checkout -q main
"$git_bin" clone -q "$tmp/tick-repo" "$tmp/factory-wt"
touch "$tmp/not-a-directory"
mkdir -p "$tmp/failure-metrics" "$tmp/failure-sessions" "$tmp/failure-claims"

set +e
PATH="$stubs:$PATH" \
  PYTHONDONTWRITEBYTECODE=1 \
  FACTORY_WORKTREE="$tmp/factory-wt" \
  FACTORY_LOG_FILE="$tmp/not-a-directory/tick.jsonl" \
  FACTORY_METRICS_DIR="$tmp/failure-metrics" \
  FACTORY_SESSION_LOG_DIR="$tmp/failure-sessions" \
  FACTORY_CLAIM_DIR="$tmp/failure-claims" \
  bash "$tmp/tick-repo/dev-ops/factory/tick.sh" --dry-run \
    >"$tmp/failure-stdout" 2>"$tmp/failure-stderr"
rc=$?
set -e

if [[ "$rc" -ne 0 ]]; then
  printf 'FAIL: telemetry write failure changed tick exit code to %s\n' "$rc" >&2
  cat "$tmp/failure-stderr" >&2
  exit 1
fi
if ! grep -q 'failed to emit telemetry event' "$tmp/failure-stderr"; then
  printf 'FAIL: telemetry write failure warning missing\n' >&2
  exit 1
fi
telemetry_errors="$(awk '/^factory_telemetry_errors_last /{print $2}' "$tmp/failure-metrics/factory_tick.prom")"
if [[ "$telemetry_errors" -le 0 ]]; then
  printf 'FAIL: telemetry write failures were not counted\n' >&2
  exit 1
fi
printf 'PASS: telemetry write failures are counted without failing the tick\n'

# A failure writing only the final tick_end event must still be reflected in the
# Prometheus snapshot. Earlier event writes succeed in this case.
mkdir -p "$tmp/final-metrics" "$tmp/final-sessions" "$tmp/final-claims"
set +e
PATH="$stubs:$PATH" \
  PYTHONDONTWRITEBYTECODE=1 \
  FACTORY_EMIT_FAIL_EVENT="tick_end" \
  FACTORY_WORKTREE="$tmp/factory-wt" \
  FACTORY_LOG_FILE="$tmp/final-events.jsonl" \
  FACTORY_METRICS_DIR="$tmp/final-metrics" \
  FACTORY_SESSION_LOG_DIR="$tmp/final-sessions" \
  FACTORY_CLAIM_DIR="$tmp/final-claims" \
  bash "$tmp/tick-repo/dev-ops/factory/tick.sh" --dry-run \
    >"$tmp/final-stdout" 2>"$tmp/final-stderr"
rc=$?
set -e

if [[ "$rc" -ne 0 ]]; then
  printf 'FAIL: final telemetry write failure changed tick exit code to %s\n' "$rc" >&2
  cat "$tmp/final-stderr" >&2
  exit 1
fi
if ! grep -q 'failed to emit telemetry event tick_end' "$tmp/final-stderr"; then
  printf 'FAIL: final telemetry write failure warning missing\n' >&2
  exit 1
fi
telemetry_errors="$(awk '/^factory_telemetry_errors_last /{print $2}' "$tmp/final-metrics/factory_tick.prom")"
if [[ "$telemetry_errors" -ne 1 ]]; then
  printf 'FAIL: final telemetry write failure metric expected 1, got %s\n' "$telemetry_errors" >&2
  exit 1
fi
printf 'PASS: final tick_end write failure is counted in metrics\n'
