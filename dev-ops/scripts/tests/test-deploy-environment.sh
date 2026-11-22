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
if [[ "${1:-}" == "issue" && "${2:-}" == "list" && -n "${GH_EXISTING_ISSUE:-}" ]]; then
  printf '%s\n' "$GH_EXISTING_ISSUE"
fi
exit 0
EOF
cat > "$stubs/docker" <<'EOF'
#!/usr/bin/env bash
# Controlled docker compose stub. Fixtures let a test feed realistic compose
# output, including the log lines that must never reach a public issue.
args=" $* "
if [[ "$args" == *" up "* && -n "${FAIL_COMPOSE_UP:-}" ]]; then
  exit 1
fi
if [[ "$args" == *" logs "* && -n "${COMPOSE_LOG_FIXTURE:-}" ]]; then
  cat "$COMPOSE_LOG_FIXTURE"
fi
if [[ "$args" == *" ps "* && -n "${COMPOSE_PS_FIXTURE:-}" ]]; then
  cat "$COMPOSE_PS_FIXTURE"
fi
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
  # A provisioned deploy has a compose file; failure reporting needs it to
  # gather the host-local log tail and ps status.
  mkdir -p "$checkout/projects/sauna"
  echo "services: {}" > "$checkout/projects/sauna/docker-compose.yml"
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

# A deploy checkout with no git identity at all (the reported bug) must still
# record and push the deploy metadata. The script pins a local identity, so the
# run has no global git config and an empty HOME.
identity_origin="$tmp/identity-origin.git"
identity_fixture="$tmp/identity-fixture"
identity_deploy="$tmp/identity-deploy"
make_deploy_checkout "$identity_origin" "$identity_fixture"
"$git_bin" clone -q "$identity_origin" "$identity_deploy"
no_identity_home="$tmp/no-identity-home"
mkdir -p "$no_identity_home"
out="$tmp/out-identity.log"
if run_deploy "$out" \
    DEPLOY_DIR="$identity_deploy" \
    DEPLOY_LOCK_FILE="$tmp/locks/identity.lock" \
    XDG_STATE_HOME="$tmp/state" \
    HOME="$no_identity_home" \
    GIT_CONFIG_GLOBAL=/dev/null \
    GIT_CONFIG_NOSYSTEM=1 \
    TMPDIR="$tmp/tmp" \
    -- qa; then
  pass
else
  fail "deploy in a checkout without a git identity should succeed"
fi
[[ -n "$("$git_bin" -C "$identity_deploy" config --local --get user.email || true)" ]] \
  && pass || fail "deploy checkout gets a local user.email"
[[ -n "$("$git_bin" -C "$identity_deploy" config --local --get user.name || true)" ]] \
  && pass || fail "deploy checkout gets a local user.name"
"$git_bin" -C "$identity_origin" log -1 --format=%s main | grep -q "^chore(dev-ops): record qa deploy " \
  && pass || fail "deploy metadata is committed and pushed without a preconfigured identity"

# A failing metadata commit must not be swallowed by "|| true": the deploy
# still succeeds (it recorded its events), but the log explains why
# environments.yaml went stale.
printf '#!/bin/sh\necho "simulated commit failure" >&2\nexit 1\n' \
  > "$identity_deploy/.git/hooks/pre-commit"
chmod +x "$identity_deploy/.git/hooks/pre-commit"
origin_sha_before="$("$git_bin" -C "$identity_origin" rev-parse main)"
out="$tmp/out-commit-failure.log"
if run_deploy "$out" \
    DEPLOY_DIR="$identity_deploy" \
    DEPLOY_LOCK_FILE="$tmp/locks/identity.lock" \
    XDG_STATE_HOME="$tmp/state" \
    HOME="$no_identity_home" \
    GIT_CONFIG_GLOBAL=/dev/null \
    GIT_CONFIG_NOSYSTEM=1 \
    TMPDIR="$tmp/tmp" \
    -- qa; then
  pass
else
  fail "a metadata commit failure must not fail a successful deploy"
fi
grep -q "WARNING: failed to commit deploy metadata" "$out" \
  && pass || fail "commit failure is logged instead of swallowed"
grep -q "simulated commit failure" "$out" \
  && pass || fail "commit failure includes git's own error output"
[[ "$("$git_bin" -C "$identity_origin" rev-parse main)" == "$origin_sha_before" ]] \
  && pass || fail "failed metadata commit is not pushed"
rm -f "$identity_deploy/.git/hooks/pre-commit"

# A failing metadata push must be visible too, and must not fail the deploy.
printf '#!/bin/sh\necho "simulated push failure" >&2\nexit 1\n' \
  > "$identity_deploy/.git/hooks/pre-push"
chmod +x "$identity_deploy/.git/hooks/pre-push"
origin_sha_before="$("$git_bin" -C "$identity_origin" rev-parse main)"
out="$tmp/out-push-failure.log"
if run_deploy "$out" \
    DEPLOY_DIR="$identity_deploy" \
    DEPLOY_LOCK_FILE="$tmp/locks/identity.lock" \
    XDG_STATE_HOME="$tmp/state" \
    HOME="$no_identity_home" \
    GIT_CONFIG_GLOBAL=/dev/null \
    GIT_CONFIG_NOSYSTEM=1 \
    TMPDIR="$tmp/tmp" \
    -- qa; then
  pass
else
  fail "a metadata push failure must not fail a successful deploy"
fi
grep -q "WARNING: failed to push deploy metadata" "$out" \
  && pass || fail "push failure is logged instead of swallowed"
grep -q "simulated push failure" "$out" \
  && pass || fail "push failure includes git's own error output"
[[ "$("$git_bin" -C "$identity_origin" rev-parse main)" == "$origin_sha_before" ]] \
  && pass || fail "failed metadata push leaves origin unchanged"
rm -f "$identity_deploy/.git/hooks/pre-push"

# I-002: a failed deploy must never publish compose log lines to the public QA
# failure issue. QA runs EMAIL_MODE=log, so compose logs hold login codes and
# email recipients/bodies. Feed such a log through the stub and assert that the
# issue body carries only metadata and service status, while the full raw log
# stays in a host-local file.
leak_log="$tmp/leak-compose.log"
cat > "$leak_log" <<'EOF'
backend  | email (log mode) to resident@example.invalid
backend  | Your login code is 481516 for resident@example.invalid
backend  | booking confirmation for unit 7 sent to resident@example.invalid
frontend | GET /healthz 200
EOF
ps_out="$tmp/compose-ps.out"
cat > "$ps_out" <<'EOF'
NAME                SERVICE     STATUS
booking-backend-1   backend     Up 2 minutes
booking-frontend-1  frontend    Up 2 minutes
EOF

leak_origin="$tmp/leak-origin.git"
leak_fixture="$tmp/leak-fixture"
leak_deploy="$tmp/leak-deploy"
make_deploy_checkout "$leak_origin" "$leak_fixture"
"$git_bin" clone -q "$leak_origin" "$leak_deploy"
leak_home="$tmp/leak-home"
mkdir -p "$leak_home"

: > "$gh_log"
out="$tmp/out-leak.log"
if run_deploy "$out" \
    DEPLOY_DIR="$leak_deploy" \
    DEPLOY_LOCK_FILE="$tmp/locks/leak.lock" \
    HOME="$leak_home" \
    XDG_STATE_HOME= \
    GIT_CONFIG_GLOBAL=/dev/null \
    GIT_CONFIG_NOSYSTEM=1 \
    TMPDIR="$tmp/tmp" \
    FAIL_COMPOSE_UP=1 \
    COMPOSE_LOG_FIXTURE="$leak_log" \
    COMPOSE_PS_FIXTURE="$ps_out" \
    -- qa; then
  fail "compose-up failure should fail the deploy"
else
  pass
fi
grep -q "docker compose up failed" "$out" \
  && pass || fail "compose-up failure reached the failure path"
grep -q "issue create" "$gh_log" \
  && pass || fail "compose-up failure surfaced as a GitHub issue"

# Nothing sensitive from the compose log may appear in the published body.
grep -qF "email (log mode" "$gh_log" \
  && fail "issue body leaked an email (log mode line" || pass
grep -qF "resident@example.invalid" "$gh_log" \
  && fail "issue body leaked an email address" || pass
grep -qF "Your login code" "$gh_log" \
  && fail "issue body leaked a login code" || pass

# The body still carries only the safe metadata and the ps service status.
grep -qF "Failing command:" "$gh_log" && pass || fail "issue body has failing command"
grep -qF "Commit:" "$gh_log" && pass || fail "issue body has commit"
grep -qF "Time (UTC):" "$gh_log" && pass || fail "issue body has time"
grep -qF "Service status:" "$gh_log" && pass || fail "issue body has service status"
grep -qF "booking-backend-1" "$gh_log" && pass || fail "issue body has ps status rows"
grep -qF "Log tail:" "$gh_log" \
  && fail "issue body still has a Log tail section" || pass

# The full raw log is written to the host-only state dir under HOME.
log_file_count=$(find "$leak_home/.local/state/booking-deploy" -maxdepth 1 -type f -name '*.log' 2>/dev/null | wc -l || true)
[[ "$log_file_count" -ge 1 ]] && pass || fail "host-local deploy log file created under HOME"
first_log_file=$(find "$leak_home/.local/state/booking-deploy" -maxdepth 1 -type f -name '*.log' 2>/dev/null | head -1 || true)
grep -qF "Your login code is 481516" "$first_log_file" \
  && pass || fail "host-local log keeps the full raw log"
[[ "$(stat -c '%a' "$first_log_file")" == "600" ]] \
  && pass || fail "host-local log is private to the deploy user (mode 600)"
grep -qF "Full deploy log (host only): $first_log_file" "$gh_log" \
  && pass || fail "issue body names the host log path"

# XDG_STATE_HOME, when set, takes precedence for the host-local log dir.
xdg_state="$tmp/xdg-state"
: > "$gh_log"
out="$tmp/out-leak-xdg.log"
if run_deploy "$out" \
    DEPLOY_DIR="$leak_deploy" \
    DEPLOY_LOCK_FILE="$tmp/locks/leak-xdg.lock" \
    HOME="$leak_home" \
    XDG_STATE_HOME="$xdg_state" \
    GIT_CONFIG_GLOBAL=/dev/null \
    GIT_CONFIG_NOSYSTEM=1 \
    TMPDIR="$tmp/tmp" \
    FAIL_COMPOSE_UP=1 \
    COMPOSE_LOG_FIXTURE="$leak_log" \
    COMPOSE_PS_FIXTURE="$ps_out" \
    -- qa; then
  fail "compose-up failure with XDG_STATE_HOME should fail the deploy"
else
  pass
fi
[[ -n "$(find "$xdg_state/booking-deploy" -maxdepth 1 -type f -name '*.log' 2>/dev/null | head -1 || true)" ]] \
  && pass || fail "host-local deploy log file created under XDG_STATE_HOME"
grep -qF "resident@example.invalid" "$gh_log" \
  && fail "issue body leaked an email address (XDG case)" || pass

# When an open QA failure issue already exists, the same scrubbed body is a
# comment. With no state dir set, the host log falls back under TMPDIR.
: > "$gh_log"
out="$tmp/out-leak-comment.log"
if run_deploy "$out" \
    DEPLOY_DIR="$leak_deploy" \
    DEPLOY_LOCK_FILE="$tmp/locks/leak-comment.lock" \
    HOME= \
    XDG_STATE_HOME= \
    GIT_CONFIG_GLOBAL=/dev/null \
    GIT_CONFIG_NOSYSTEM=1 \
    TMPDIR="$tmp/tmp" \
    GH_EXISTING_ISSUE=42 \
    FAIL_COMPOSE_UP=1 \
    COMPOSE_LOG_FIXTURE="$leak_log" \
    COMPOSE_PS_FIXTURE="$ps_out" \
    -- qa; then
  fail "compose-up failure with an existing issue should fail the deploy"
else
  pass
fi
grep -q "issue comment 42" "$gh_log" \
  && pass || fail "failure posted as a comment on the existing issue"
grep -qF "resident@example.invalid" "$gh_log" \
  && fail "issue comment leaked an email address" || pass
grep -qF "Your login code" "$gh_log" \
  && fail "issue comment leaked a login code" || pass
tmp_log=$(find "$tmp/tmp/booking-deploy-$(id -u)" -maxdepth 1 -type f -name '*.log' 2>/dev/null | head -1 || true)
[[ -n "$tmp_log" ]] && pass || fail "host-local deploy log created in TMPDIR fallback"
grep -qF "Your login code is 481516" "$tmp_log" \
  && pass || fail "TMPDIR fallback log keeps the full raw log"

# A deploy checkout left mid-rebase by an interrupted run must recover on the
# next deploy instead of failing repeatedly at "git rebase origin/$BRANCH"
# (issue #324).
rebase_origin="$tmp/rebase-origin.git"
rebase_fixture="$tmp/rebase-fixture"
rebase_deploy="$tmp/rebase-deploy"
make_deploy_checkout "$rebase_origin" "$rebase_fixture"
"$git_bin" clone -q "$rebase_origin" "$rebase_deploy"

# Create a conflicting local commit so rebasing onto an advanced origin stops.
"$git_bin" -C "$rebase_deploy" checkout -q main
echo "local change" > "$rebase_deploy/rebase-conflict.txt"
"$git_bin" -C "$rebase_deploy" add rebase-conflict.txt
"$git_bin" -C "$rebase_deploy" commit -qm "local: conflicting change"

advance="$tmp/rebase-advance"
"$git_bin" clone -q "$rebase_origin" "$advance"
"$git_bin" -C "$advance" config user.email "deploy-test@example.invalid"
"$git_bin" -C "$advance" config user.name "deploy-test"
echo "origin change" > "$advance/rebase-conflict.txt"
"$git_bin" -C "$advance" add rebase-conflict.txt
"$git_bin" -C "$advance" commit -qm "origin: conflicting change"
"$git_bin" -C "$advance" push -q origin main

"$git_bin" -C "$rebase_deploy" fetch -q origin main
set +e
"$git_bin" -C "$rebase_deploy" rebase origin/main >/dev/null 2>&1
rebase_rc=$?
set -e
[[ "$rebase_rc" -ne 0 ]] && pass || fail "test setup should leave rebase in conflict"
[[ -d "$rebase_deploy/.git/rebase-merge" || -d "$rebase_deploy/.git/rebase-apply" ]] \
  && pass || fail "test setup should leave rebase state behind"

out="$tmp/out-rebase-recovery.log"
if run_deploy "$out" \
    DEPLOY_DIR="$rebase_deploy" \
    DEPLOY_LOCK_FILE="$tmp/locks/rebase.lock" \
    XDG_STATE_HOME="$tmp/state" \
    TMPDIR="$tmp/tmp" \
    -- qa; then
  pass
else
  fail "deploy should recover from an interrupted rebase"
fi
grep -q "aborting interrupted rebase in deploy checkout" "$out" \
  && pass || fail "recovery log mentions aborted rebase"
grep -q "deploy complete" "$out" && pass || fail "deploy completes after rebase recovery"
[[ ! -d "$rebase_deploy/.git/rebase-merge" && ! -d "$rebase_deploy/.git/rebase-apply" ]] \
  && pass || fail "rebase state removed after recovery"
expected_sha="$("$git_bin" -C "$rebase_origin" rev-parse main)"
"$git_bin" -C "$rebase_deploy" merge-base --is-ancestor "$expected_sha" HEAD \
  && pass || fail "recovered checkout is based on origin tip"

# Local commits that diverged from origin must not block deploys; the deploy
# checkout mirrors origin exactly.
diverge_origin="$tmp/diverge-origin.git"
diverge_fixture="$tmp/diverge-fixture"
diverge_deploy="$tmp/diverge-deploy"
make_deploy_checkout "$diverge_origin" "$diverge_fixture"
"$git_bin" clone -q "$diverge_origin" "$diverge_deploy"
"$git_bin" -C "$diverge_deploy" checkout -q main
echo "local-only" > "$diverge_deploy/local-only.txt"
"$git_bin" -C "$diverge_deploy" add local-only.txt
"$git_bin" -C "$diverge_deploy" commit -qm "local: unpushed metadata-like commit"
local_sha="$("$git_bin" -C "$diverge_deploy" rev-parse HEAD)"
origin_sha="$("$git_bin" -C "$diverge_origin" rev-parse main)"
[[ "$local_sha" != "$origin_sha" ]] && pass || fail "test setup should create diverged local commit"

out="$tmp/out-diverge.log"
if run_deploy "$out" \
    DEPLOY_DIR="$diverge_deploy" \
    DEPLOY_LOCK_FILE="$tmp/locks/diverge.lock" \
    XDG_STATE_HOME="$tmp/state" \
    TMPDIR="$tmp/tmp" \
    -- qa; then
  pass
else
  fail "deploy should recover from diverged local commits"
fi
"$git_bin" -C "$diverge_deploy" merge-base --is-ancestor "$origin_sha" HEAD \
  && pass || fail "diverged deploy checkout is based on origin tip"
"$git_bin" -C "$diverge_deploy" merge-base --is-ancestor "$local_sha" HEAD \
  && fail "diverged local-only commit should not remain on deployed branch" || pass
[[ ! -f "$diverge_deploy/local-only.txt" ]] \
  && pass || fail "diverged local-only file removed from deploy checkout"

# The deploy script itself must no longer contain a Log tail section.
grep -q "Log tail" "$SCRIPT" \
  && fail "deploy script still has a Log tail section" || pass

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
