#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
SCRIPT="$SCRIPT_DIR/../deploy-environment.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." >/dev/null && pwd)"
PASS=0; FAIL=0
fail() { echo "FAIL: $*" >&2; FAIL=$((FAIL+1)); }
pass() { PASS=$((PASS+1)); }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

stubs="$tmp/bin"
mkdir -p "$stubs"
gh_log="$tmp/gh.log"
: > "$gh_log"

cat > "$stubs/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_LOG"
exit 0
EOF
cat > "$stubs/docker" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$stubs/curl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$stubs/gh" "$stubs/docker" "$stubs/curl"
# Resolve the real git binary; the script itself uses it extensively.
git_bin="$(command -v git)"

# Build a bare origin plus a deploy checkout that mirrors a provisioned
# environment, so the script can run end-to-end without Docker or the network.
make_deploy_checkout() {
  local origin="$1" checkout="$2"
  "$git_bin" init -q --bare "$origin"
  "$git_bin" init -q "$checkout"
  "$git_bin" -C "$checkout" config user.email "deploy-test@example.invalid"
  "$git_bin" -C "$checkout" config user.name "deploy-test"
  mkdir -p "$checkout/dev-ops"
  cp "$REPO_ROOT/dev-ops/environments.yaml" "$checkout/dev-ops/environments.yaml"
  echo "# deploy fixture" > "$checkout/README.md"
  "$git_bin" -C "$checkout" add -A
  "$git_bin" -C "$checkout" commit -qm "test: fixture checkout"
  "$git_bin" -C "$checkout" branch -M main
  "$git_bin" -C "$checkout" remote add origin "$origin"
  "$git_bin" -C "$checkout" push -q origin main
  "$git_bin" -C "$origin" symbolic-ref HEAD refs/heads/main
}

# run_deploy OUT_VAR EXTRA_ENV... -- ARGS
# Runs the script with stubbed docker/curl/gh and a fixture deploy checkout.
run_deploy() {
  local out="$1"; shift
  local envs=()
  while [[ $# -gt 0 && "$1" != "--" ]]; do envs+=("$1"); shift; done
  [[ $# -gt 0 ]] && shift
  set +e
  env PATH="$stubs:$PATH" GH_LOG="$gh_log" "${envs[@]}" \
    "$SCRIPT" "$@" >"$out" 2>&1
  local rc=$?
  set -e
  return "$rc"
}

fixture="$tmp/fixture"
origin="$tmp/origin.git"
deploy="$tmp/deploy"
make_deploy_checkout "$origin" "$fixture"
"$git_bin" clone -q "$origin" "$deploy"

out="$tmp/out-explicit.log"
lockdir="$tmp/locks"
if run_deploy "$out" \
    DEPLOY_DIR="$deploy" \
    DEPLOY_LOCK_FILE="$lockdir/qa.lock" \
    XDG_RUNTIME_DIR="$tmp/runtime" \
    TMPDIR="$tmp/tmp" \
    -- qa; then
  pass
else
  fail "deploy with explicit DEPLOY_LOCK_FILE should succeed"
fi
grep -qF "lock: $lockdir/qa.lock" "$out" && pass || fail "explicit lock path used"
[[ -f "$lockdir/qa.lock" ]] && pass || fail "explicit lock file created"
grep -q "starting compose" "$out" && pass || fail "deploy proceeds past the lock step"
grep -q "deploy complete" "$out" && pass || fail "deploy completes with fixture checkout"

# A pinned but unwritable lock path must fail loudly, surface a deployment
# failure issue, and never fall back to a different path silently.
if [[ "$EUID" -eq 0 ]]; then
  echo "SKIP: unwritable lock assertions are meaningless as root" >&2
else
  readonly_dir="$tmp/read-only"
  mkdir -p "$readonly_dir"
  chmod 500 "$readonly_dir"
  : > "$gh_log"
  out="$tmp/out-unwritable.log"
  if run_deploy "$out" \
      DEPLOY_DIR="$deploy" \
      DEPLOY_LOCK_FILE="$readonly_dir/qa.lock" \
      TMPDIR="$tmp/tmp" \
      -- qa; then
    fail "unwritable explicit lock path should fail"
  else
    pass
  fi
  grep -qF "lock path not writable: $readonly_dir/qa.lock" "$out" \
    && pass || fail "unwritable lock path reported"
  grep -q "could not open a deploy lock" "$out" \
    && pass || fail "lock failure explains itself"
  grep -q "issue create" "$gh_log" \
    && pass || fail "lock failure surfaced as a GitHub issue"
  chmod 700 "$readonly_dir"
fi

# Without an explicit path, an unusable runtime dir falls through to a
# per-user lock under TMPDIR instead of aborting on a shared stale file.
if [[ "$EUID" -eq 0 ]]; then
  echo "SKIP: fallback lock assertions are meaningless as root" >&2
else
  readonly_runtime="$tmp/read-only-runtime"
  mkdir -p "$readonly_runtime" "$tmp/tmp"
  chmod 500 "$readonly_runtime"
  out="$tmp/out-fallback.log"
  if run_deploy "$out" \
      DEPLOY_DIR="$deploy" \
      XDG_RUNTIME_DIR="$readonly_runtime" \
      TMPDIR="$tmp/tmp" \
      -- qa; then
    pass
  else
    fail "deploy should fall back to a writable lock path"
  fi
  grep -qF "lock path not writable: $readonly_runtime/booking-deploy-qa.lock" "$out" \
    && pass || fail "unwritable runtime lock path reported"
  expected_lock="$tmp/tmp/booking-deploy-qa-$(id -u).lock"
  grep -qF "lock: $expected_lock" "$out" && pass || fail "per-user fallback lock used"
  grep -q "deploy complete" "$out" && pass || fail "fallback deploy completes"
  chmod 700 "$readonly_runtime"
fi

# Dry run reports the lock path it would use and creates nothing.
out="$tmp/out-dry.log"
dry_lock="$tmp/dry-locks/qa.lock"
if DEPLOY_LOCK_FILE="$dry_lock" "$SCRIPT" qa --dry-run >"$out" 2>&1; then
  pass
else
  fail "dry run should succeed"
fi
grep -qF "lock=$dry_lock" "$out" && pass || fail "dry run prints lock path"
[[ ! -e "$dry_lock" ]] && pass || fail "dry run does not create the lock file"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
