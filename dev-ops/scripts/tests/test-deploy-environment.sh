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
    XDG_STATE_HOME="$tmp/state" \
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

# A pinned but unusable lock path must fail loudly, surface a deployment
# failure issue, and never fall back to a different path silently. /proc is
# not writable even for root, so this case runs on every host.
: > "$gh_log"
out="$tmp/out-unusable.log"
if run_deploy "$out" \
    DEPLOY_DIR="$deploy" \
    DEPLOY_LOCK_FILE="/proc/nonexistent/qa.lock" \
    TMPDIR="$tmp/tmp" \
    -- qa; then
  fail "unusable explicit lock path should fail"
else
  pass
fi
grep -qF "lock path not writable: /proc/nonexistent/qa.lock" "$out" \
  && pass || fail "unusable lock path reported"
grep -q "could not open a deploy lock" "$out" \
  && pass || fail "lock failure explains itself"
grep -q "issue create" "$gh_log" \
  && pass || fail "lock failure surfaced as a GitHub issue"
grep -q "starting compose" "$out" \
  && fail "unusable lock path must not reach the deploy steps" || pass

# Without an explicit path, an unusable state dir falls through to a per-user
# lock under TMPDIR instead of aborting on a shared stale file.
mkdir -p "$tmp/tmp" "$tmp/state"
out="$tmp/out-fallback.log"
if run_deploy "$out" \
    DEPLOY_DIR="$deploy" \
    XDG_STATE_HOME="/proc/nonexistent" \
    TMPDIR="$tmp/tmp" \
    -- qa; then
  pass
else
  fail "deploy should fall back to a writable lock path"
fi
grep -qF "lock path not writable: /proc/nonexistent/booking-deploy-qa.lock" "$out" \
  && pass || fail "unusable state lock path reported"
expected_lock="$tmp/tmp/booking-deploy-qa-$(id -u).lock"
grep -qF "lock: $expected_lock" "$out" && pass || fail "per-user fallback lock used"
grep -q "deploy complete" "$out" && pass || fail "fallback deploy completes"

# The reported bug shape: a writable directory holding a lock file the deploy
# user cannot open (a root-owned file in /var/lock). The deploy must fall
# through to the next candidate instead of aborting. Root ignores file modes,
# so this case is unprivileged-only.
if [[ "$EUID" -eq 0 ]]; then
  echo "SKIP: stale root-owned lock file shape is not reproducible as root" >&2
else
  shadow_state="$tmp/shadow-state"
  mkdir -p "$shadow_state"
  shadow_lock="$shadow_state/booking-deploy-qa.lock"
  : > "$shadow_lock"
  chmod 000 "$shadow_lock"
  out="$tmp/out-stale.log"
  if run_deploy "$out" \
      DEPLOY_DIR="$deploy" \
      XDG_STATE_HOME="$shadow_state" \
      TMPDIR="$tmp/tmp" \
      -- qa; then
    pass
  else
    fail "unreadable stale lock file should not abort the deploy"
  fi
  grep -qF "lock path not writable: $shadow_lock" "$out" \
    && pass || fail "stale unreadable lock reported"
  grep -q "deploy complete" "$out" && pass || fail "deploy completes past stale lock"
  chmod 600 "$shadow_lock"
fi

# The default lock path is deterministic for a user, so a timer run and a cron
# run serialize against each other.
for attempt in 1 2; do
  out="$tmp/out-deterministic-$attempt.log"
  if run_deploy "$out" \
      DEPLOY_DIR="$deploy" \
      XDG_STATE_HOME="$tmp/state" \
      TMPDIR="$tmp/tmp" \
      -- qa; then
    pass
  else
    fail "deploy with a state-dir lock should succeed (attempt $attempt)"
  fi
  grep -qF "lock: $tmp/state/booking-deploy-qa.lock" "$out" \
    && pass || fail "deterministic state-dir lock used (attempt $attempt)"
done

# Dry run reports the first lock path it would try and creates nothing.
out="$tmp/out-dry.log"
dry_lock="$tmp/dry-locks/qa.lock"
if env PATH="$stubs:$PATH" GH_LOG="$gh_log" DEPLOY_LOCK_FILE="$dry_lock" \
    "$SCRIPT" qa --dry-run >"$out" 2>&1; then
  pass
else
  fail "dry run should succeed"
fi
grep -qF "lock=$dry_lock" "$out" && pass || fail "dry run prints lock path"
[[ ! -e "$dry_lock" ]] && pass || fail "dry run does not create the lock file"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
