#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." >/dev/null && pwd)"
SCRIPT="$REPO_ROOT/dev-ops/scripts/monitoring.sh"

PASS=0
FAIL=0
pass() { PASS=$((PASS+1)); }
fail() { echo "FAIL: $*" >&2; FAIL=$((FAIL+1)); }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Stub docker to record args.
stub="$tmp/bin"
mkdir -p "$stub"
docker_log="$tmp/docker.log"
cat > "$stub/docker" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$DOCKER_LOG"
exit 0
STUB
chmod +x "$stub/docker"

run_script() {
  local out="$1"; shift
  set +e
  PATH="$stub:$PATH" DOCKER_LOG="$docker_log" "$SCRIPT" "$@" >"$out" 2>&1
  local rc=$?
  set -e
  return "$rc"
}

# Help
out="$tmp/help.out"
if run_script "$out" --help; then pass; else fail "--help should exit 0"; fi
grep -q "Usage:" "$out" && pass || fail "help shows usage"

# Missing args
out="$tmp/missing.out"
if run_script "$out"; then fail "missing args should fail"; else pass; fi

# Unknown command
out="$tmp/unknown-cmd.out"
if run_script "$out" factory nope; then fail "unknown command should fail"; else pass; fi
grep -q "unknown command" "$out" && pass || fail "unknown command message"

# Unknown stack dir
out="$tmp/unknown-stack.out"
if run_script "$out" nosuchproject status; then fail "unknown stack should fail"; else pass; fi
grep -q "unknown monitoring stack" "$out" && pass || fail "unknown stack message"

# Status for factory uses factory compose file and project name
: > "$docker_log"
out="$tmp/factory-status.out"
if run_script "$out" factory status; then pass; else fail "factory status should succeed"; fi
grep -q "dev-ops/factory/monitoring/docker-compose.yml" "$docker_log" && pass || fail "factory compose file used"
grep -q -- "-p factory-monitoring" "$docker_log" && pass || fail "factory project name used"

# Status for sauna uses project compose file and project name
: > "$docker_log"
out="$tmp/sauna-status.out"
if run_script "$out" sauna status; then pass; else fail "sauna status should succeed"; fi
grep -q "projects/sauna/monitoring/compose.yaml" "$docker_log" && pass || fail "sauna compose file used"
grep -q -- "-p sauna-monitoring" "$docker_log" && pass || fail "sauna project name used"

# Down without --volumes must not pass -v
: > "$docker_log"
out="$tmp/down.out"
if run_script "$out" sauna down; then pass; else fail "down should succeed"; fi
if grep -q -- " down -v" "$docker_log"; then fail "down without --volumes must not remove volumes"; else pass; fi
grep -q -- " down --remove-orphans" "$docker_log" && pass || fail "down calls docker compose down"

# Down --volumes in non-interactive mode requires --yes
: > "$docker_log"
out="$tmp/down-volumes-no.out"
if run_script "$out" sauna down --volumes < /dev/null; then fail "down --volumes without confirmation should fail in non-interactive mode"; else pass; fi
grep -q "refusing to remove volumes" "$out" && pass || fail "volume removal refusal message"
if grep -q -- " down -v" "$docker_log"; then fail "volumes not removed without confirmation"; else pass; fi

# Down --volumes --yes removes volumes
: > "$docker_log"
out="$tmp/down-volumes-yes.out"
if run_script "$out" sauna down --volumes --yes; then pass; else fail "down --volumes --yes should succeed"; fi
grep -q -- " down -v --remove-orphans" "$docker_log" && pass || fail "down --volumes --yes removes volumes"

# Up requires env file
out="$tmp/up-no-env.out"
if run_script "$out" sauna up --env-file "$tmp/nope.env"; then fail "up with missing env should fail"; else pass; fi
grep -q "missing env file" "$out" && pass || fail "missing env file message"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
