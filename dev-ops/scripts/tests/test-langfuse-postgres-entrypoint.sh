#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." >/dev/null && pwd)"
SCRIPT="$REPO_ROOT/dev-ops/factory/monitoring/scripts/langfuse-postgres-entrypoint.sh"

PASS=0
FAIL=0
pass() { PASS=$((PASS+1)); }
fail() { echo "FAIL: $*" >&2; FAIL=$((FAIL+1)); }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
stub="$tmp/bin"
mkdir -p "$stub"
entrypoint_log="$tmp/entrypoint.log"
cat > "$stub/docker-entrypoint.sh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$ENTRYPOINT_LOG"
STUB
chmod +x "$stub/docker-entrypoint.sh"

run_entrypoint() {
  local out="$1" pg_major="$2"
  shift 2
  set +e
  env PATH="$stub:$PATH" ENTRYPOINT_LOG="$entrypoint_log" PG_MAJOR="$pg_major" \
    PGDATA="$tmp/data" "$SCRIPT" "$@" >"$out" 2>&1
  local rc=$?
  set -e
  return "$rc"
}

rm -f "$entrypoint_log"
out="$tmp/fresh.out"
if run_entrypoint "$out" 18 postgres -c test=1; then
  pass
else
  fail "a fresh data directory should start"
fi
[[ -f "$entrypoint_log" ]] && pass || fail "fresh start should call the official entrypoint"
grep -q '^postgres -c test=1$' "$entrypoint_log" 2>/dev/null && pass || fail "entrypoint arguments should be preserved"

mkdir -p "$tmp/data"
printf '18\n' > "$tmp/data/PG_VERSION"
rm -f "$entrypoint_log"
out="$tmp/matching.out"
if run_entrypoint "$out" 18 postgres; then
  pass
else
  fail "a matching PostgreSQL major should start"
fi
[[ -f "$entrypoint_log" ]] && pass || fail "matching major should call the official entrypoint"

printf '17\n' > "$tmp/data/PG_VERSION"
rm -f "$entrypoint_log"
out="$tmp/mismatch.out"
if run_entrypoint "$out" 18 postgres; then
  fail "a PostgreSQL 17 data directory must not start with PostgreSQL 18"
else
  pass
fi
[[ ! -f "$entrypoint_log" ]] && pass || fail "a major mismatch must not reach the official entrypoint"
grep -q 'Refusing to open PostgreSQL 17 data with PostgreSQL 18 binaries' "$out" \
  && pass || fail "a major mismatch should explain the refused versions"
grep -q 'dump/restore or pg_upgrade' "$out" && pass || fail "a major mismatch should require a supported migration"

out="$tmp/missing-major.out"
if env PATH="$stub:$PATH" ENTRYPOINT_LOG="$entrypoint_log" PGDATA="$tmp/data" \
  "$SCRIPT" postgres >"$out" 2>&1; then
  fail "an existing data directory must not start without PG_MAJOR"
else
  pass
fi
grep -q 'PG_MAJOR is unset' "$out" && pass || fail "missing PG_MAJOR should fail closed"

printf 'PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
