#!/usr/bin/env bash
#
# tick.sh - one tick of the software factory.
#
# (see header comments in git history)
#
set -euo pipefail

# cron (and other minimal environments) may not include ~/.opencode/bin on PATH
export PATH="${HOME}/.opencode/bin:${PATH}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

MODELS_CONFIG="${MODELS_CONFIG:-$SCRIPT_DIR/models.yaml}"
APPROVED_LABEL="owner approved"
PLAN_MARKER='<!-- factory:plan -->'
BUILD_MARKER='<!-- factory:build -->'
DRY_RUN=0
TICK_RC=0
INFRA_FAILURE=0
USAGE_FILLED_REASON=""
ON_USAGE_FILLED="${FACTORY_ON_USAGE_FILLED:-backup}"
MAX_FIX_SESSIONS="${FACTORY_MAX_FIX_SESSIONS:-1}"
FREE_MODEL="${FACTORY_FREE_MODEL:-opencode-go/beam-free}"
FACTORY_LOGIN="${FACTORY_LOGIN:-}"
FACTORY_GITHUB_APP_ID="${FACTORY_GITHUB_APP_ID:-}"
FACTORY_GITHUB_APP_PRIVATE_KEY_FILE="${FACTORY_GITHUB_APP_PRIVATE_KEY_FILE:-}"
FACTORY_GITHUB_APP_PRIVATE_KEY="${FACTORY_GITHUB_APP_PRIVATE_KEY:-}"
FACTORY_GITHUB_INSTALLATION_ID="${FACTORY_GITHUB_INSTALLATION_ID:-}"

# Observability and hardening knobs.
FACTORY_LOG_FILE="${FACTORY_LOG_FILE:-${XDG_STATE_HOME:-$HOME/.local/state}/factory/tick.jsonl}"
FACTORY_ENV="${FACTORY_ENV:-dev}"
FACTORY_CONTAINER_MODE="${FACTORY_CONTAINER_MODE:-0}"
FACTORY_CLAIM_TTL="${FACTORY_CLAIM_TTL:-7200}"
FACTORY_CLAIM_DIR="${FACTORY_CLAIM_DIR:-/tmp/factory-claims}"
FACTORY_GH_RETRIES="${FACTORY_GH_RETRIES:-3}"
FACTORY_SESSION_TIMEOUT="${FACTORY_SESSION_TIMEOUT:-3600}"
FACTORY_SESSION_LOG_DIR="${FACTORY_SESSION_LOG_DIR:-/tmp/opencode}"
FACTORY_LOG_SESSION_OUTPUT="${FACTORY_LOG_SESSION_OUTPUT:-tail}"
FACTORY_PRESERVE_SESSION_LOGS="${FACTORY_PRESERVE_SESSION_LOGS:-on-failure}" # always|on-failure|never
HOSTNAME_VAL="$(hostname 2>/dev/null || echo unknown)"

umask 077
mkdir -p "$(dirname "$FACTORY_LOG_FILE")" "$FACTORY_SESSION_LOG_DIR" "$FACTORY_CLAIM_DIR" 2>/dev/null || true
chmod 700 "$(dirname "$FACTORY_LOG_FILE")" "$FACTORY_SESSION_LOG_DIR" "$FACTORY_CLAIM_DIR" 2>/dev/null || true
: >> "$FACTORY_LOG_FILE" 2>/dev/null || true
chmod 600 "$FACTORY_LOG_FILE" 2>/dev/null || true

usage() {
  cat <<'USAGE'
Usage: tick.sh [--dry-run] [--on-usage-filled=backup|skip|fail] [--max-fix-sessions=N]

Options:
  --dry-run                 Select and log actions without starting sessions.
  --on-usage-filled=MODE    backup|skip|fail when model usage/quota is filled.
  --max-fix-sessions=N      Maximum fix sessions per tick (default: 1).
  -h, --help                Show this help.

Environment (key):
  FACTORY_LOG_FILE, FACTORY_ENV, FACTORY_CONTAINER_MODE, FACTORY_SESSION_TIMEOUT,
  FACTORY_CLAIM_TTL, FACTORY_CLAIM_DIR, FACTORY_GH_RETRIES,
  FACTORY_SESSION_LOG_DIR, FACTORY_LOG_SESSION_OUTPUT (tail|metadata),
  FACTORY_PRESERVE_SESSION_LOGS (on-failure|always|never),
  FACTORY_WORKTREE, FACTORY_CONFIG_TAG, FACTORY_FREE_MODEL, FACTORY_ON_USAGE_FILLED,
  FACTORY_LOGIN, FACTORY_GITHUB_APP_ID, FACTORY_GITHUB_APP_PRIVATE_KEY_FILE,
  FACTORY_GITHUB_APP_PRIVATE_KEY, FACTORY_GITHUB_INSTALLATION_ID.
USAGE
}

log() { printf '[factory-tick] %s\n' "$*"; }
die() { printf '[factory-tick] ERROR: %s\n' "$*" >&2; exit 1; }

classify_gh_text() {
  printf '%s' "$1" | python3 "$SCRIPT_DIR/lib/factory.py" classify-gh - 2>/dev/null || echo other
}

classify_git_text() {
  printf '%s' "$1" | python3 "$SCRIPT_DIR/lib/factory.py" classify-git - 2>/dev/null || echo other
}

should_retry_category() {
  local cat="$1"
  [[ "$cat" == "transient" || "$cat" == "rate_limit" ]]
}

gh_run_capture() {
  # Usage: gh_run_capture <label> <command...>
  # Sets GH_OUT, GH_ERR, GH_RC, GH_CATEGORY. Retries transient/rate_limit.
  local label="$1"; shift
  local attempt=1 max="$FACTORY_GH_RETRIES" rc=0 out err cat delay
  GH_OUT=""
  GH_ERR=""
  GH_RC=0
  GH_CATEGORY=""
  while :; do
    err="$(mktemp)"
    if out="$("$@" 2>"$err")"; then
      GH_OUT="$out"
      GH_ERR="$(cat "$err" 2>/dev/null || true)"
      GH_RC=0
      GH_CATEGORY=""
      rm -f "$err"
      return 0
    else
      rc=$?
    fi
    GH_ERR="$(cat "$err" 2>/dev/null || true)"
    rm -f "$err"
    GH_OUT="${out:-}"
    GH_RC=$rc
    if [[ "$1" == "git" ]]; then
      cat="$(classify_git_text "$GH_ERR")"
    else
      cat="$(classify_gh_text "$GH_ERR")"
    fi
    GH_CATEGORY="$cat"
    emit_event gh_op_retry op="$label" attempt="$attempt" max_attempts="$max" exit_code="$rc" category="$cat"
    if [[ $attempt -ge $max ]] || ! should_retry_category "$cat"; then
      return $rc
    fi
    delay=$((attempt*2))
    [[ "$cat" == "rate_limit" ]] && delay=$((attempt*10))
    sleep "$delay"
    attempt=$((attempt+1))
  done
}

gh_retry() {
  # Backward-compatible wrapper for simple callers.
  gh_run_capture "gh_retry:$1" "$@"
}

mint_factory_github_token() {
  # Mint a short-lived GitHub App installation token and export it as GH_TOKEN.
  # No-op when app credentials are not configured (falls back to ambient gh auth).
  # Never prints the token.
  if [[ -z "${FACTORY_GITHUB_APP_ID:-}" ]]; then
    return 0
  fi
  local key_file="${FACTORY_GITHUB_APP_PRIVATE_KEY_FILE:-}"
  local tmp_key=""
  if [[ -z "$key_file" && -n "${FACTORY_GITHUB_APP_PRIVATE_KEY:-}" ]]; then
    tmp_key="$(mktemp)"
    (umask 077; printf '%s' "$FACTORY_GITHUB_APP_PRIVATE_KEY" > "$tmp_key")
    key_file="$tmp_key"
  fi
  [[ -n "$key_file" && -f "$key_file" ]] || die "FACTORY_GITHUB_APP_ID set but no readable private key (FACTORY_GITHUB_APP_PRIVATE_KEY_FILE/FACTORY_GITHUB_APP_PRIVATE_KEY)"
  local repo_arg=""
  if [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
    repo_arg="--repo $GITHUB_REPOSITORY"
  fi
  local token
  token="$(python3 "$SCRIPT_DIR/lib/mint_github_app_token.py" \
    --app-id "$FACTORY_GITHUB_APP_ID" \
    --key-file "$key_file" \
    ${FACTORY_GITHUB_INSTALLATION_ID:+--installation-id "$FACTORY_GITHUB_INSTALLATION_ID"} \
    ${repo_arg} \
    --repo-root "$REPO_ROOT" 2>/tmp/factory-mint-err)" || {
      local err; err="$(cat /tmp/factory-mint-err 2>/dev/null || true)"
      rm -f /tmp/factory-mint-err
      [[ -n "$tmp_key" ]] && rm -f "$tmp_key"
      die "failed to mint factory GitHub App token: $err"
    }
  rm -f /tmp/factory-mint-err
  [[ -n "$tmp_key" ]] && rm -f "$tmp_key"
  [[ -n "$token" ]] || die "minted empty factory token"
  export GH_TOKEN="$token"
  export GITHUB_TOKEN="$token"
  log "factory GitHub App token minted (login filter: ${FACTORY_LOGIN:-unset})"
}
# Best-effort structured event emitter. Writes one JSON object to FACTORY_LOG_FILE.
# Never raises; never touches stdout/stderr.
emit_event() {
  local event="${1:-}"; shift || true
  python3 - "$event" "$FACTORY_LOG_FILE" "$TICK_ID" "$DRY_RUN" "$ON_USAGE_FILLED" "$FACTORY_ENV" "$HOSTNAME_VAL" "$@" << 'PYEOF' >/dev/null 2>&1 || true
import datetime, json, sys

event = sys.argv[1]
path = sys.argv[2]
tick_id = sys.argv[3]
dry_run = sys.argv[4]
on_usage = sys.argv[5]
env = sys.argv[6] or "dev"
host = sys.argv[7]
pairs = sys.argv[8:]

obj = {}
obj["schema_version"] = 1
obj["ts"] = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")
obj["service.name"] = "factory-tick"
obj["deployment.environment"] = env
obj["host.name"] = host
obj["tick_id"] = tick_id
obj["dry_run"] = (dry_run == "1")
obj["on_usage_filled"] = on_usage
obj["event"] = event

for p in pairs:
    if "=" in p:
        k, v = p.split("=", 1)
        obj[k] = v

try:
    with open(path, "a", encoding="utf-8") as f:
        f.write(json.dumps(obj, ensure_ascii=False) + "\n")
except Exception:
    pass
PYEOF
}

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --on-usage-filled=*) ON_USAGE_FILLED="${arg#*=}" ;;
    --max-fix-sessions=*) MAX_FIX_SESSIONS="${arg#*=}" ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $arg" ;;
  esac
done

case "$ON_USAGE_FILLED" in
  backup|skip|fail) ;;
  *) die "invalid --on-usage-filled value: $ON_USAGE_FILLED (use backup, skip, or fail)" ;;
esac

[[ "$MAX_FIX_SESSIONS" =~ ^[0-9]+$ ]] || die "invalid --max-fix-sessions value: $MAX_FIX_SESSIONS (use a non-negative integer)"
[[ "$FACTORY_GH_RETRIES" =~ ^[0-9]+$ && "$FACTORY_GH_RETRIES" -ge 1 ]] || die "invalid FACTORY_GH_RETRIES: $FACTORY_GH_RETRIES"
[[ "$FACTORY_CLAIM_TTL" =~ ^[0-9]+$ ]] || die "invalid FACTORY_CLAIM_TTL: $FACTORY_CLAIM_TTL"
[[ "$FACTORY_SESSION_TIMEOUT" =~ ^[0-9]+$ ]] || die "invalid FACTORY_SESSION_TIMEOUT: $FACTORY_SESSION_TIMEOUT"
case "$FACTORY_LOG_SESSION_OUTPUT" in tail|metadata) ;; *) die "invalid FACTORY_LOG_SESSION_OUTPUT: $FACTORY_LOG_SESSION_OUTPUT" ;; esac
case "$FACTORY_PRESERVE_SESSION_LOGS" in always|on-failure|never) ;; *) die "invalid FACTORY_PRESERVE_SESSION_LOGS: $FACTORY_PRESERVE_SESSION_LOGS" ;; esac

[[ -f "$MODELS_CONFIG" ]] || die "config not found: $MODELS_CONFIG"
python3 "$SCRIPT_DIR/lib/factory.py" validate-models "$MODELS_CONFIG" >/dev/null 2>&1 || die "invalid models config: $MODELS_CONFIG"
command -v gh >/dev/null || die "gh is required"
command -v opencode >/dev/null || die "opencode is required"
command -v python3 >/dev/null || die "python3 is required"
python3 -c 'import yaml' 2>/dev/null || die "PyYAML is required (pip install pyyaml)"

# Mint a least-privilege factory token (if configured) before any gh/git work.
mint_factory_github_token
export FACTORY_LOGIN

TICK_ID="$(python3 -c 'import secrets;print(secrets.token_hex(16))' 2>/dev/null || echo 00000000000000000000000000000000)"
TICK_START_MS="$(date +%s%3N)"

on_exit() {
  local rc=$?
  local now dur
  now="$(date +%s%3N 2>/dev/null || echo "$TICK_START_MS")"
  dur=$((now - TICK_START_MS))
  emit_event tick_end exit_code="$rc" duration_ms="$dur"
  exit "$rc"
}
trap on_exit EXIT
on_signal() {
  local sig="$1"
  emit_event tick_interrupted signal="$sig"
  exit 130
}
trap 'on_signal INT' INT
trap 'on_signal TERM' TERM

# Do not overlap ticks: a slow session must not pile up followers.
exec 9>"$(git rev-parse --git-dir)/factory-tick.lock"
emit_event tick_start opencode_version="$(opencode --version 2>/dev/null || echo unknown)"
if ! flock -n 9; then
  log "previous tick still running; exiting"
  emit_event lock_skipped
  exit 0
fi

# Print the number of the oldest open issue with no labels, or nothing.
# Distinguishes "no candidates" (success, empty output) from infra/auth failures.
# Sets OLDEST_UNLABELED_ISSUE on success.
OLDEST_UNLABELED_ISSUE=""
oldest_unlabeled_issue() {
  OLDEST_UNLABELED_ISSUE=""
  if ! gh_run_capture "oldest_unlabeled_issue" gh issue list --state open --limit 200 --json number,labels,createdAt \
    --jq '[.[] | select((.labels | length) == 0)] | sort_by(.createdAt) | .[0].number // empty'; then
    emit_event gh_op_failed op="oldest_unlabeled_issue" category="${GH_CATEGORY:-other}" exit_code="${GH_RC:-1}"
    case "${GH_CATEGORY:-}" in auth|permission|rate_limit|transient) INFRA_FAILURE=1 ;; esac
    return 1
  fi
  OLDEST_UNLABELED_ISSUE="$GH_OUT"
  printf '%s\n' "$GH_OUT"
}

# Legacy inline discovery helpers retained for reference; active paths use
# discover_build_candidates.py / discover_fix_candidates.py.
approved_build_candidates() {
  python3 - "$APPROVED_LABEL" << 'PYEOF'
import json, math, subprocess, sys

label = sys.argv[1]


def gh_json(*args):
    r = subprocess.run(["gh", *args], capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError((r.stderr or r.stdout or "").strip())
    return json.loads(r.stdout or "null")


def by_created(it):
    n = it["number"]
    created = it.get("createdAt") or "9999"
    return (created, n)


def emit(items, prio):
    def key(it):
        n = it["number"]
        created = it.get("createdAt") or "9999"
        if n in prio:
            pc, pn, bo = prio[n]
            return (0, pc, pn, bo, created, n)
        return (1, "9999", math.inf, math.inf, created, n)

    for it in sorted(items, key=key):
        print(it["number"])


try:
    issues = gh_json(
        "issue",
        "list",
        "--state",
        "open",
        "--label",
        label,
        "--limit",
        "200",
        "--json",
        "number,createdAt",
    )
except Exception:
    issues = []
if not issues:
    raise SystemExit

try:
    repo = gh_json("repo", "view", "--json", "owner,nameWithOwner")
    owner = repo["owner"]["login"]
    full = repo["nameWithOwner"]

    projects = []
    for q in (
        "query($login:String!){ user(login:$login){ projectsV2(first:50){ nodes{ number id createdAt closed } } } }",
        "query($login:String!){ organization(login:$login){ projectsV2(first:50){ nodes{ number id createdAt closed } } } }",
    ):
        try:
            pdata = gh_json("api", "graphql", "-f", f"query={q}", "-F", f"login={owner}")["data"]
            for key in ("user", "organization"):
                nodes = ((pdata.get(key) or {}).get("projectsV2") or {}).get("nodes") or []
                projects.extend([n for n in nodes if n])
        except Exception:
            pass
    seen_p = set()
    uniq_projects = []
    for p in projects:
        n = p.get("number")
        if n not in seen_p:
            seen_p.add(n)
            uniq_projects.append(p)

    items_q = (
        "query($id:ID!, $after:String){ node(id:$id){ ... on ProjectV2{"
        " items(first:100, after:$after){ nodes{ content{ __typename"
        " ... on Issue{ number repository{ nameWithOwner } }"
        " ... on PullRequest{ number repository{ nameWithOwner } } }"
        " fieldValueByName(name:\"Build order\"){ __typename"
        " ... on ProjectV2ItemFieldNumberValue{ number }"
        " ... on ProjectV2ItemFieldTextValue{ text } } }"
        " pageInfo{ hasNextPage endCursor } } } } }"
    )

    prio = {}
    for p in uniq_projects:
        if p.get("closed") or not p.get("id"):
            continue
        pnum = p.get("number")
        pcreated = p.get("createdAt") or "9999"
        after = None
        while True:
            try:
                args = ["api", "graphql", "-f", f"query={items_q}", "-f", f"id={p['id']}"]
                if after:
                    args += ["-f", f"after={after}"]
                conn = ((gh_json(*args).get("data") or {}).get("node") or {}).get("items") or {}
            except Exception:
                break
            for it in conn.get("nodes") or []:
                content = it.get("content") or {}
                if (content.get("__typename") or "").lower() != "issue":
                    continue
                repo_name = ((content.get("repository") or {}).get("nameWithOwner") or "").strip()
                if repo_name != full:
                    continue
                num = content.get("number")
                if not isinstance(num, int):
                    continue
                fv = it.get("fieldValueByName") or {}
                bo = fv.get("number")
                if bo is None:
                    bo = fv.get("text")
                try:
                    bof = float(bo)
                except Exception:
                    bof = math.inf
                cand = (pcreated, pnum or math.inf, bof)
                if num not in prio or cand < prio[num]:
                    prio[num] = cand
            page = conn.get("pageInfo") or {}
            if not page.get("hasNextPage"):
                break
            after = page.get("endCursor")
            if not after:
                break

    emit(issues, prio)
except Exception as e:
    sys.stderr.write(f"[factory-tick] project priority unavailable, using issue age: {e}\n")
    for it in sorted(issues, key=by_created):
        print(it["number"])
PYEOF
}

# Print fix candidates ... (unchanged)
fix_pr_candidates() {
  python3 - << 'PYEOF'
import json, re, subprocess, sys

FAIL = {"FAILURE", "FAILED", "ERROR", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED", "STARTUP_FAILURE", "STALE"}


def gh_json(*args):
    r = subprocess.run(["gh", *args], capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError((r.stderr or r.stdout or "").strip())
    return json.loads(r.stdout or "null")


def check_state(item):
    if not isinstance(item, dict):
        return ""
    st = (item.get("state") or item.get("conclusion") or item.get("status") or "").upper()
    if item.get("__typename") == "CheckRun" and (item.get("status") or "").upper() not in ("COMPLETED", ""):
        return "PENDING"
    return st


try:
    prs = gh_json(
        "pr", "list", "--state", "open", "--limit", "100",
        "--json", "number,headRefName,headRefOid,mergeable,reviewDecision,statusCheckRollup,isDraft,createdAt",
    )
except Exception as e:
    sys.stderr.write(f"[factory-tick] fix-pr discovery unavailable: {e}\n")
    raise SystemExit

rows = []
for pr in prs or []:
    if pr.get("isDraft"):
        continue
    head = pr.get("headRefName") or ""
    m = re.match(r"^factory/issue-(\d+)$", head)
    if not m:
        continue
    issue = int(m.group(1))
    sha = (pr.get("headRefOid") or "").strip()
    if not sha:
        continue
    reasons = []
    rollup = pr.get("statusCheckRollup") or []
    if isinstance(rollup, list):
        for item in rollup:
            st = check_state(item)
            if st in FAIL:
                reasons.append("failing-checks")
                break
    rd = (pr.get("reviewDecision") or "").upper()
    if rd == "CHANGES_REQUESTED":
        reasons.append("changes-requested")
    mergeable = (pr.get("mergeable") or "").upper()
    if mergeable == "CONFLICTING":
        reasons.append("conflicts")
    if not reasons:
        continue
    reasons = sorted(set(reasons))
    rkey = ",".join(reasons)
    marker = f"<!-- factory:fix-pr:{sha}:{rkey} -->"
    rows.append((pr.get("createdAt") or "9999", pr.get("number"), issue, sha, rkey, marker))

for _created, prnum, issue, sha, rkey, marker in sorted(rows):
    print(f"{prnum}\t{issue}\t{sha}\t{rkey}\t{marker}")
PYEOF
}

has_marker() {
  local marker_json
  marker_json="$(python3 -c 'import json, sys; print(json.dumps(sys.argv[1]))' "$2")"
  if ! gh_run_capture "has_marker_issue" gh issue view "$1" --json comments \
    --jq "[.comments[].body | contains($marker_json)] | any"; then
    emit_event gh_op_failed op="has_marker_issue" issue="$1" category="${GH_CATEGORY:-other}" exit_code="${GH_RC:-1}"
    case "${GH_CATEGORY:-}" in auth|permission|rate_limit|transient) INFRA_FAILURE=1 ;; esac
    echo "false"
    return 0
  fi
  printf '%s\n' "${GH_OUT:-false}"
}

has_pr_marker() {
  local marker_json
  marker_json="$(python3 -c 'import json, sys; print(json.dumps(sys.argv[1]))' "$2")"
  if ! gh_run_capture "has_pr_marker" gh pr view "$1" --json comments \
    --jq "[.comments[].body | contains($marker_json)] | any"; then
    emit_event gh_op_failed op="has_pr_marker" pr="$1" category="${GH_CATEGORY:-other}" exit_code="${GH_RC:-1}"
    case "${GH_CATEGORY:-}" in auth|permission|rate_limit|transient) INFRA_FAILURE=1 ;; esac
    echo "false"
    return 0
  fi
  printf '%s\n' "${GH_OUT:-false}"
}

issue_labels() {
  if ! gh_run_capture "issue_labels" gh issue view "$1" --json labels --jq '.labels[].name'; then
    emit_event gh_op_failed op="issue_labels" issue="$1" category="${GH_CATEGORY:-other}" exit_code="${GH_RC:-1}"
    case "${GH_CATEGORY:-}" in auth|permission|rate_limit|transient) INFRA_FAILURE=1 ;; esac
    return 1
  fi
  printf '%s\n' "$GH_OUT"
}

open_factory_pr_for_issue() {
  if ! gh_run_capture "open_factory_pr_for_issue" gh pr list --state open --head "factory/issue-$1" --json number --jq '.[0].number // empty'; then
    emit_event gh_op_failed op="open_factory_pr_for_issue" issue="$1" category="${GH_CATEGORY:-other}" exit_code="${GH_RC:-1}"
    case "${GH_CATEGORY:-}" in auth|permission|rate_limit|transient) INFRA_FAILURE=1 ;; esac
    return 1
  fi
  printf '%s\n' "$GH_OUT"
}

model_for_labels() {
  python3 "$SCRIPT_DIR/lib/factory.py" model-for-labels "$MODELS_CONFIG" "$@"
}


is_usage_filled() {
  local out="${1,,}"
  local res reason
  res="$(printf '%s' "$out" | python3 "$SCRIPT_DIR/lib/factory.py" is-usage-filled - 2>/dev/null)" || res="false	"
  reason="${res#*$'\t'}"
  res="${res%%$'\t'*}"
  USAGE_FILLED_REASON="${reason:-unknown}"
  if [[ "$res" == "true" ]]; then
    return 0
  fi
  # fallback substring checks
  if [[ "$out" == *"usage limit"* ]]; then USAGE_FILLED_REASON="usage limit"; return 0; fi
  if [[ "$out" == *"limit exceeded"* ]]; then USAGE_FILLED_REASON="limit exceeded"; return 0; fi
  if [[ "$out" == *"rate limit"* ]]; then USAGE_FILLED_REASON="rate limit"; return 0; fi
  if [[ "$out" == *"quota"* && "$out" == *"exceed"* ]]; then USAGE_FILLED_REASON="quota exceeded"; return 0; fi
  if [[ "$out" == *"usage"* && "$out" == *"exceed"* ]]; then USAGE_FILLED_REASON="usage exceeded"; return 0; fi
  USAGE_FILLED_REASON=""
  return 1
}


# prompts unchanged (abbreviated here but included)
plan_prompt() { # $1 issue number
  cat << EOF
You are the planning agent of this software factory. Turn GitHub issue #$1
into a planned, categorized issue.

1. Read it: gh issue view $1 --comments
2. Post one comment with a concrete, minimal implementation plan. The comment
   body must start with this exact marker line:

$PLAN_MARKER

3. Categorize the issue with labels (see gh label list). If the task is
   large, also add the heavy-build-task label. Never add the
   "$APPROVED_LABEL" label - only the repository owner applies it.

Do not modify any code or files.

If a follow-up issue must be filed, use the /create-github-issue command
(see .opencode/commands/create-github-issue.md) rather than ad hoc
gh issue create, so the body follows the agentic template and passes
dev-ops/scripts/validate-issue-body.sh.
EOF
}

build_prompt() { # $1 issue number
  cat << EOF
You are the builder agent of this software factory. Implement GitHub issue
#$1 and land it on the base branch. Follow the builder agent workflow in
.opencode/agents/builder.md (single owner of the issue-to-merged-PR lifecycle).

Load and follow these OpenCode skills (use the skill tool) as they apply:
- \`implement\` - build the issue from its spec/plan.
- \`tdd\` - drive red-green-refactor when the project has tests.
- \`code-review\` - review changes before landing when available.
- \`diagnosing-bugs\` - use for hard bugs or performance regressions.
- \`domain-modeling\` - use when changing domain terminology, CQRS/event-sourced
  models, or project glossary/ADR-worthy decisions.
- \`frontend-design\` / \`webapp-testing\` - use for \`product/frontend/\` UI
  work and Playwright/browser verification when relevant.
- \`pr\` - when opening the pull request, write the PR body in that format
  (Summary, Evidence, Merge Danger). Include \`Closes #$1\` in the body.
- \`caveman\` - concise reporting style for issue/PR summaries and comments where
  appropriate.
- \`investigate-first\`, \`lean-build\`, \`surgical-patch\`, \`safe-refactor\`,
  \`migration\`, \`verify-and-stop\` - work-pattern skills; apply only when
  relevant (investigate before changing, minimal build, targeted edits, safe
  refactors, migrations, stop after verification).
- \`caveman-commit\`, \`caveman-review\`, \`caveman-compress\` - concise commit
  messages, PR review, and context compression; use when drafting commits/PR
  bodies or compressing context.

Apply the skills above conditionally based on the issue; do not force them on
every issue. If a follow-up issue must be filed, use the
\`/create-github-issue\` command (see
\`.opencode/commands/create-github-issue.md\`) rather than ad hoc
\`gh issue create\`, so the body follows the agentic template and passes
\`dev-ops/scripts/validate-issue-body.sh\`.
Factory delivery rules (these override generic skill defaults where they
conflict):
1. Read the issue and its plan: gh issue view $1 --comments
2. Inspect repository/working-tree state with git status in the primary
   checkout; never modify it. Create an isolated per-issue worktree and a
   descriptive feature branch (factory/issue-$1) based on the latest
   origin/main. Reuse an existing worktree/branch if present and verify its
   state. Keep all changes isolated to the worktree. Persist execution state in
   <worktree>/.factory-deliver-state.json (gitignored) and mirror milestones
   as GitHub comments. Track issue URL, base branch, worktree, branch,
   progress, commits, PR number/URL, CI statuses, remediation attempts,
   blockers, merge status.
3. If acceptance criteria are missing/ambiguous, document the blocker and stop.
4. Implement the smallest change that satisfies the issue. Follow AGENTS.md; add
   tests where the project has tests. Keep the change minimal.
5. Review staged changes, commit with clear messages, push the branch.
6. Draft PR creation: detect an existing PR for the branch first
   (gh pr list --head factory/issue-$1); reuse it. Otherwise create in draft
   mode: gh pr create --draft against the base branch. Include Closes #$1.
   Do not mark ready for review automatically.
7. CI monitoring: identify checks (gh pr checks), wait (gh pr checks --watch).
   Distinguish success/failed/pending/cancelled/skipped; do not treat pending
   as success. Retrieve logs for failures (gh run view, gh run view --log-failed).
   Run local checks first (gofmt -l ., go vet ./..., go test ./...,
   go build ./cmd/server for backend). Do not proceed while required checks run
   or fail.
8. CI remediation: fix root cause in the worktree, add/update tests, run checks
   locally, commit and push, wait for CI. Retry at most 3 cycles. Never disable
   tests, weaken gates, edit CI config to bypass, or make unrelated changes.
   If unfixable, document root cause and report blocker.
9. Readiness and merge: verify all required checks passed, acceptance criteria
   met, no blockers/unrelated changes, reviews/protection satisfied, PR
   mergeable, no conflicts. If all pass, transition draft to ready if required
   (gh pr ready), verify again, attempt merge using repo strategy, then verify
   actual merge via gh pr view --json state,mergedAt. Record final status.
   If blocked, do not bypass; report the blocking condition and leave PR for
   human intervention. Distinguish attempt from successful merge.
10. On successful merge: remove worktree and branch only after GitHub confirms
    merge and no uncommitted changes remain. On failure/interruption: retain
    worktree and report path.
11. Post one comment on the issue summarizing what was merged. The comment
    body must start with this exact marker line:

$BUILD_MARKER
EOF
}

fix_prompt() { # $1 PR number, $2 issue number, $3 reasons, $4 marker
  cat << EOF
You are the fix agent of this software factory. Pull request #$1 (for issue
#$2, branch factory/issue-$2) is open but blocked from merge. Make it
mergeable. Resume the builder lifecycle from .opencode/agents/fixer.md rather
than duplicating logic.

Blocking reasons reported by GitHub: $3
(failing-checks = status/CI failures; changes-requested = review requested
changes; conflicts = merge conflicts / not mergeable.)

1. Read context: gh pr view $1 --comments; gh pr checks $1 || true; gh issue view $2 --comments
2. Locate/reuse the existing worktree for the PR branch; verify branch and status.
   Read <worktree>/.factory-deliver-state.json if present and verify against
   actual Git/GitHub state. Never modify unrelated working directories.
3. Conflicts: fetch and rebase onto origin/main. Resolve by understanding both
   sides; never blanket-accept one side. Re-run tests and push with
   --force-with-lease.
4. Failing checks: retrieve logs (gh run view, gh run view --log-failed),
   reproduce/fix root cause in the worktree, add/update tests, run checks
   locally.
5. Requested changes: address each comment; if unclear or conflicting, reply on
   the PR and stop rather than guessing.
6. Push fixes to the PR branch. Watch CI: gh pr checks $1 --watch. Wait for
   ALL required checks and security analyses (Backend CI, Security, Semgrep)
   to complete and pass. Do NOT merge until every check is green, security
   analysis clean, PR mergeable, and no requested changes.
7. CI remediation retry limit: 3 cycles. Never disable tests, weaken quality
   gates, modify CI config to bypass failures, or make unrelated changes.
8. Readiness: verify required checks, acceptance criteria, no blockers, reviews/
   protection, mergeability, no conflicts. If blocked by reviews, protection,
   permissions, conflicts, or policy: do not bypass; report the blocking
   condition and leave the PR for human intervention.
9. If eligible, transition draft to ready if required (gh pr ready), verify
   again, attempt merge using repo strategy, and verify actual merge via
   gh pr view $1 --json state,mergedAt. Record final status in state file.
   Distinguish attempt from successfully merged PR.
10. Post one comment on PR #$1 summarizing what you fixed and the merge/result
    status. The comment body must start with this exact marker line (required
    for factory idempotency):

$4

If the PR was merged, also ensure issue #$2 has a comment starting with:

$BUILD_MARKER

summarizing what was merged (add it if missing).
EOF
}

normalize_model() {
  local m="$1"
  [[ -z "$m" ]] && { printf '%s' "$m"; return; }
  case "${m%%#*}" in
    opencode-go/beam-free)
      m="opencode-go/beam-free#high"
      ;;
  esac
  printf '%s' "$m"
}

run_opencode() {
  local sandbox=()
  if [[ "$FACTORY_CONTAINER_MODE" == "1" ]] && command -v bwrap >/dev/null 2>&1; then
    sandbox=(bwrap --die-with-parent --cap-drop ALL --proc /proc --dev /dev --unshare-pid --unshare-ipc --unshare-uts --ro-bind / / --bind "$FACTORY_WORKTREE" "$FACTORY_WORKTREE" --bind "$HOME" "$HOME" --bind /tmp /tmp --bind "$FACTORY_SESSION_LOG_DIR" "$FACTORY_SESSION_LOG_DIR" --chdir "$PWD")
    emit_event container_mode reason="bwrap-sandbox"
  elif [[ "$FACTORY_CONTAINER_MODE" == "1" ]]; then
    log "container mode requested but bwrap unavailable; using host runtime"
    emit_event container_mode reason="fallback-host"
  fi
  local model
  model="$(normalize_model "$2")"
  local prompt_file
  mkdir -p "$FACTORY_SESSION_LOG_DIR" 2>/dev/null || true
  prompt_file="$(mktemp "$FACTORY_SESSION_LOG_DIR/factory-prompt-XXXXXX.txt" 2>/dev/null || mktemp /tmp/opencode/factory-prompt-XXXXXX.txt 2>/dev/null || echo "$FACTORY_SESSION_LOG_DIR/factory-prompt-$$.txt")"
  (umask 077; printf '%s' "$4" > "$prompt_file")
  chmod 600 "$prompt_file" 2>/dev/null || true
  local args=(run --auto --title "$1" --format json --file "$prompt_file" "Follow the attached factory prompt.")
  [[ -n "$model" ]] && args+=(--model "$model")
  [[ -n "$3" ]] && args+=(--agent "$3")
  local rc=0
  if [[ "$FACTORY_SESSION_TIMEOUT" =~ ^[0-9]+$ ]] && [[ "$FACTORY_SESSION_TIMEOUT" -gt 0 ]]; then
    timeout --signal=TERM --kill-after=30 "$FACTORY_SESSION_TIMEOUT" "${sandbox[@]}" opencode "${args[@]}"
    rc=$?
  else
    "${sandbox[@]}" opencode "${args[@]}"
    rc=$?
  fi
  rm -f "$prompt_file" 2>/dev/null || true
  return $rc
}

finalize_session_log() { # path, success(0/1)
  local path="$1" success="$2"
  [[ -z "$path" || "$path" == "/dev/null" ]] || [[ ! -f "$path" ]] && return 0
  chmod 600 "$path" 2>/dev/null || true
  case "$FACTORY_PRESERVE_SESSION_LOGS" in
    always) return 0 ;;
    never) rm -f "$path" 2>/dev/null || true; return 0 ;;
    on-failure)
      if [[ "$success" == "1" ]]; then rm -f "$path" 2>/dev/null || true; fi
      ;;
  esac
}

start_session() { # $1 kind, $2 ref, $3 title, $4 model, $5 backup_model, $6 prompt
  local kind="$1" ref="$2" title="$3" model="$4" backup="$5" prompt="$6"
  local agent=""
  case "$kind" in
    plan) agent="planner" ;;
    build) agent="builder" ;;
    fix) agent="fixer" ;;
  esac
  local out status=0 session_start_ms duration tail_out
  session_start_ms="$(date +%s%3N)"
  local logfile="/dev/null"
  if [[ "$FACTORY_LOG_SESSION_OUTPUT" != "metadata" ]]; then
    logfile="$FACTORY_SESSION_LOG_DIR/factory-${kind}-${ref}.log"
    (umask 077; : > "$logfile")
    chmod 600 "$logfile" 2>/dev/null || true
  fi
  log "starting $kind session for #$ref (model: ${model:-opencode default}, agent: ${agent:-default})"
  if [[ "$kind" == "fix" ]]; then
    emit_event session_start kind="$kind" pr="$ref" model="${model:-}" backup_model="${backup:-}"
  else
    emit_event session_start kind="$kind" issue="$ref" model="${model:-}" backup_model="${backup:-}"
  fi
  set +e
  set -o pipefail
  out="$(run_opencode "$title" "$model" "$agent" "$prompt" 2>&1 | tee "$logfile")"
  status=$?
  set +o pipefail
  set -e
  session_id="$(printf '%s\n' "$out" | python3 -c 'import sys,json\nfor line in sys.stdin:\n try:\n  o=json.loads(line); sid=o.get("sessionID")\n  if sid: print(sid); break\n except Exception: pass' 2>/dev/null | head -1)"
  if [[ $status -eq 0 ]]; then
    printf '%s\n' "$out"
    duration=$(( $(date +%s%3N) - session_start_ms ))
    if [[ "$kind" == "fix" ]]; then
      emit_event session_ok kind="$kind" pr="$ref" model="${model:-}" exit_code=0 duration_ms="$duration" outcome="ok" session_id="${session_id:-}"
    else
      emit_event session_ok kind="$kind" issue="$ref" model="${model:-}" exit_code=0 duration_ms="$duration" outcome="ok" session_id="${session_id:-}"
    fi
    finalize_session_log "$logfile" 1
    return 0
  fi

  printf '%s\n' "$out" >&2
  if is_usage_filled "$out"; then
    log "session for #$ref failed: usage/quota appears filled (on-usage-filled=$ON_USAGE_FILLED)"
    if [[ "$kind" == "fix" ]]; then
      emit_event usage_filled kind="$kind" pr="$ref" model="${model:-}" outcome="usage_filled" session_id="${session_id:-}" reason="$USAGE_FILLED_REASON"
    else
      emit_event usage_filled kind="$kind" issue="$ref" model="${model:-}" outcome="usage_filled" session_id="${session_id:-}" reason="$USAGE_FILLED_REASON"
    fi
    case "$ON_USAGE_FILLED" in
      backup)
        if [[ -n "$backup" && "$backup" != "$model" ]]; then
          local bout bstatus=0
          log "retrying #$ref with backup model: $backup"
          if [[ "$kind" == "fix" ]]; then
            emit_event backup_retry kind="$kind" pr="$ref" model="$backup"
          else
            emit_event backup_retry kind="$kind" issue="$ref" model="$backup"
          fi
          set +e
          set -o pipefail
          bout="$(run_opencode "$title (backup)" "$backup" "$agent" "$prompt" 2>&1 | tee -a "$logfile")"
          bstatus=$?
          set +o pipefail
          set -e
          printf '%s\n' "$bout" >&2
          if [[ $bstatus -eq 0 ]]; then
            duration=$(( $(date +%s%3N) - session_start_ms ))
            if [[ "$kind" == "fix" ]]; then
              emit_event backup_ok kind="$kind" pr="$ref" model="$backup" exit_code=0 duration_ms="$duration" outcome="backup_ok" session_id="${session_id:-}"
            else
              emit_event backup_ok kind="$kind" issue="$ref" model="$backup" exit_code=0 duration_ms="$duration" outcome="backup_ok" session_id="${session_id:-}"
            fi
            finalize_session_log "$logfile" 1
            return 0
          fi
          if ! is_usage_filled "$bout"; then
            duration=$(( $(date +%s%3N) - session_start_ms ))
            tail_out=""
            if [[ "$FACTORY_LOG_SESSION_OUTPUT" != "metadata" ]]; then tail_out="$(printf '%s' "$bout" | tail -c 16384)" || true; fi
            if [[ "$kind" == "fix" ]]; then
              emit_event session_failed kind="$kind" pr="$ref" model="$backup" exit_code="$bstatus" duration_ms="$duration" outcome="failed" session_id="${session_id:-}" output_tail="$tail_out"
            else
              emit_event session_failed kind="$kind" issue="$ref" model="$backup" exit_code="$bstatus" duration_ms="$duration" outcome="failed" session_id="${session_id:-}" output_tail="$tail_out"
            fi
            finalize_session_log "$logfile" 0
            return "$bstatus"
          fi
          log "backup model for #$ref also hit usage/quota limit"
          if [[ "$kind" == "fix" ]]; then
            emit_event usage_filled kind="$kind" pr="$ref" model="$backup" outcome="usage_filled" session_id="${session_id:-}" reason="$USAGE_FILLED_REASON"
          else
            emit_event usage_filled kind="$kind" issue="$ref" model="$backup" outcome="usage_filled" session_id="${session_id:-}" reason="$USAGE_FILLED_REASON"
          fi
        fi
        if [[ "$model" != "$FREE_MODEL" && "$backup" != "$FREE_MODEL" ]]; then
          log "retrying #$ref with free model: $FREE_MODEL"
          if [[ "$kind" == "fix" ]]; then
            emit_event free_retry kind="$kind" pr="$ref" model="$FREE_MODEL"
          else
            emit_event free_retry kind="$kind" issue="$ref" model="$FREE_MODEL"
          fi
          set +e
          set -o pipefail
          local fout fstatus=0
          fout="$(run_opencode "$title (free)" "$FREE_MODEL" "$agent" "$prompt" 2>&1 | tee -a "$logfile")"
          fstatus=$?
          set +o pipefail
          set -e
          printf '%s\n' "$fout"
          if [[ $fstatus -eq 0 ]]; then
            duration=$(( $(date +%s%3N) - session_start_ms ))
            if [[ "$kind" == "fix" ]]; then
              emit_event session_ok kind="$kind" pr="$ref" model="$FREE_MODEL" exit_code=0 duration_ms="$duration" outcome="ok" session_id="${session_id:-}"
            else
              emit_event session_ok kind="$kind" issue="$ref" model="$FREE_MODEL" exit_code=0 duration_ms="$duration" outcome="ok" session_id="${session_id:-}"
            fi
            finalize_session_log "$logfile" 1
            return 0
          fi
          duration=$(( $(date +%s%3N) - session_start_ms ))
          tail_out=""
          if [[ "$FACTORY_LOG_SESSION_OUTPUT" != "metadata" ]]; then tail_out="$(printf '%s' "$fout" | tail -c 16384)" || true; fi
          if [[ "$kind" == "fix" ]]; then
            emit_event session_failed kind="$kind" pr="$ref" model="$FREE_MODEL" exit_code="$fstatus" duration_ms="$duration" outcome="failed" session_id="${session_id:-}" output_tail="$tail_out"
          else
            emit_event session_failed kind="$kind" issue="$ref" model="$FREE_MODEL" exit_code="$fstatus" duration_ms="$duration" outcome="failed" session_id="${session_id:-}" output_tail="$tail_out"
          fi
          finalize_session_log "$logfile" 0
          return "$fstatus"
        fi
        log "no distinct free model configured for #$ref; failing"
        duration=$(( $(date +%s%3N) - session_start_ms ))
        if [[ "$kind" == "fix" ]]; then
          emit_event session_failed kind="$kind" pr="$ref" model="${model:-}" exit_code="$status" duration_ms="$duration" outcome="failed" session_id="${session_id:-}"
        else
          emit_event session_failed kind="$kind" issue="$ref" model="${model:-}" exit_code="$status" duration_ms="$duration" outcome="failed" session_id="${session_id:-}"
        fi
        finalize_session_log "$logfile" 0
        return "$status"
        ;;
      skip)
        log "skipping #$ref due to filled usage"
        if [[ "$kind" == "fix" ]]; then
          emit_event session_skipped_usage kind="$kind" pr="$ref" model="${model:-}" outcome="skipped" session_id="${session_id:-}"
        else
          emit_event session_skipped_usage kind="$kind" issue="$ref" model="${model:-}" outcome="skipped" session_id="${session_id:-}"
        fi
        finalize_session_log "$logfile" 1
        return 0
        ;;
      fail)
        if [[ "$kind" == "fix" ]]; then
          emit_event session_failed kind="$kind" pr="$ref" model="${model:-}" exit_code="$status" outcome="failed" session_id="${session_id:-}"
        else
          emit_event session_failed kind="$kind" issue="$ref" model="${model:-}" exit_code="$status" outcome="failed" session_id="${session_id:-}"
        fi
        finalize_session_log "$logfile" 0
        return "$status"
        ;;
    esac
  fi

  duration=$(( $(date +%s%3N) - session_start_ms ))
  tail_out=""
  if [[ "$FACTORY_LOG_SESSION_OUTPUT" != "metadata" ]]; then tail_out="$(printf '%s' "$out" | tail -c 16384)" || true; fi
  if [[ "$kind" == "fix" ]]; then
    emit_event session_failed kind="$kind" pr="$ref" model="${model:-}" exit_code="$status" duration_ms="$duration" outcome="failed" session_id="${session_id:-}" output_tail="$tail_out"
  else
    emit_event session_failed kind="$kind" issue="$ref" model="${model:-}" exit_code="$status" duration_ms="$duration" outcome="failed" session_id="${session_id:-}" output_tail="$tail_out"
  fi
  log "$kind session for #$ref failed (exit $status)"
  finalize_session_log "$logfile" 0
  return "$status"
}

# Guardrail drift gate (issue #164 / FAC-05): refuse to start any session when
# the agent/config guardrail files in origin/main differ from the owner-moved
# factory-config tag. Fails closed when the tag is missing or unfetchable.
FACTORY_CONFIG_TAG="${FACTORY_CONFIG_TAG:-factory-config}"
check_guardrail_drift() {
  # Force-update the local tag so a tag the owner moved on the remote is
  # honored. A missing or unfetchable tag is treated as drift (fail closed).
  if ! git fetch --quiet origin \
      "+refs/tags/${FACTORY_CONFIG_TAG}:refs/tags/${FACTORY_CONFIG_TAG}" 2>/dev/null; then
    emit_event guardrail_drift reason="tag_fetch_failed" tag="$FACTORY_CONFIG_TAG"
    die "guardrail config tag '$FACTORY_CONFIG_TAG' is missing or unfetchable; refusing to start sessions"
  fi
  if ! git diff --quiet "$FACTORY_CONFIG_TAG" origin/main -- \
      .opencode/agents opencode.jsonc AGENTS.md; then
    emit_event guardrail_drift reason="drift" tag="$FACTORY_CONFIG_TAG"
    die "guardrail files in origin/main drifted from $FACTORY_CONFIG_TAG; refusing to start sessions"
  fi
  emit_event guardrail_ok tag="$FACTORY_CONFIG_TAG"
}

# Run all factory work in an isolated git worktree so the primary checkout
# (and any in-progress user work) is never touched by build/fix sessions.
FACTORY_WORKTREE="${FACTORY_WORKTREE:-${REPO_ROOT%/*}/booking-system-factory-worktree}"
if [[ ! -e "$FACTORY_WORKTREE/.git" ]]; then
  git worktree add --detach "$FACTORY_WORKTREE" origin/main 2>/dev/null \
    || log "warning: could not create factory worktree; continuing in $REPO_ROOT"
fi
if [[ -d "$FACTORY_WORKTREE" ]]; then
  # Keep remote refs current so sessions branch from the latest origin/main
  # rather than a stale local base.
  if ! gh_run_capture "git_fetch_worktree" git -C "$FACTORY_WORKTREE" fetch --quiet --prune origin; then
    log "warning: git fetch origin failed in worktree; continuing with cached refs (category=${GH_CATEGORY:-other})"
    emit_event git_fetch_failed category="${GH_CATEGORY:-other}" exit_code="${GH_RC:-1}"
    case "${GH_CATEGORY:-}" in auth|permission|rate_limit|transient) INFRA_FAILURE=1 ;; esac
  fi
  # Never discard in-progress agent work: only reset/clean when the worktree
  # is already clean. Interrupted per-issue worktrees are preserved.
  if [[ -z "$(git -C "$FACTORY_WORKTREE" status --porcelain 2>/dev/null)" ]]; then
    git -C "$FACTORY_WORKTREE" checkout -f --detach origin/main >/dev/null 2>&1 || true
    git -C "$FACTORY_WORKTREE" reset --hard origin/main >/dev/null 2>&1 || true
    git -C "$FACTORY_WORKTREE" clean -fdx >/dev/null 2>&1 || true
  else
    log "preserving in-progress changes in $FACTORY_WORKTREE; skipping reset/clean"
    emit_event dirty_worktree_skipped_reset worktree="$FACTORY_WORKTREE" reason="worktree dirty"
  fi
  cd "$FACTORY_WORKTREE"
else
  if ! gh_run_capture "git_fetch_primary" git fetch --quiet --prune origin; then
    log "warning: git fetch origin failed; continuing with cached refs (category=${GH_CATEGORY:-other})"
    emit_event git_fetch_failed category="${GH_CATEGORY:-other}" exit_code="${GH_RC:-1}"
    case "${GH_CATEGORY:-}" in auth|permission|rate_limit|transient) INFRA_FAILURE=1 ;; esac
  fi
fi

# Fail before discovery or any session if guardrail files drifted from the
# owner-moved configuration tag (issue #164).
check_guardrail_drift

plan_issue=""
if oldest_unlabeled_issue >/dev/null; then
  plan_issue="$OLDEST_UNLABELED_ISSUE"
else
  log "failed to query unlabeled issues (infra/auth/rate-limit/transient possible); treating as discovery failure"
fi

if [[ -n "$plan_issue" && "$(has_marker "$plan_issue" "$PLAN_MARKER")" == "true" ]]; then
  log "issue #$plan_issue already planned (marker present); skipping"
  emit_event marker_skip issue="$plan_issue" reason="already planned"
  plan_issue=""
fi

# Acceptance-criteria gate (issue #91): an unlabeled ("infant") issue must
# capture explicit acceptance criteria before it is picked up by the planning
# agent. Skip planning (and leave the issue unlabeled) until they are present.
if [[ -n "$plan_issue" ]]; then
  set +e
  dev-ops/scripts/check-acceptance-criteria.sh --issue "$plan_issue" >/dev/null 2>&1
  ac_rc=$?
  set -e
  if [[ $ac_rc -eq 1 ]]; then
    log "issue #$plan_issue has no acceptance criteria; skipping planning until they are added"
    emit_event plan_skipped issue="$plan_issue" reason="missing acceptance criteria"
    plan_issue=""
  elif [[ $ac_rc -ne 0 ]]; then
    log "acceptance-criteria checker failed for #$plan_issue (rc=$ac_rc); skipping"
    emit_event plan_skipped issue="$plan_issue" reason="acceptance criteria checker error" checker_rc="$ac_rc"
    plan_issue=""
  fi
fi

acquire_claim() { # key -> prints claim path on success
  local key dir now out rc
  key="$1"
  dir="$FACTORY_CLAIM_DIR/${key}.claim"
  now="$(date +%s)"
  mkdir -p "$FACTORY_CLAIM_DIR" 2>/dev/null || true
  set +e
  out="$(python3 "$SCRIPT_DIR/lib/factory.py" claim-acquire "$dir" "$FACTORY_CLAIM_TTL" "$now" "$$" 2>/dev/null)"
  rc=$?
  set -e
  if [[ $rc -eq 0 ]]; then
    printf '%s\n' "$dir"
    return 0
  fi
  printf '%s\n' "$out"
  return 1
}
release_claim() {
  local dir="$1"
  [[ -n "$dir" ]] || return 0
  python3 "$SCRIPT_DIR/lib/factory.py" claim-release "$dir" >/dev/null 2>&1 || rm -rf "$dir" || true
}

# Build path, sub-path 1: fix open factory PRs
fix_count=0
fix_failures=0
if [[ "$MAX_FIX_SESSIONS" -gt 0 ]]; then
  fix_candidates_output=""
  fix_err="$(mktemp)"
  for attempt in $(seq 1 "$FACTORY_GH_RETRIES"); do
    if fix_candidates_output="$("$SCRIPT_DIR/discover_fix_candidates.py" 2>"$fix_err")"; then
      break
    fi
    err_text="$(cat "$fix_err" 2>/dev/null || true)"
    category="$(classify_gh_text "$err_text")"
    case "$category" in auth|permission|rate_limit|transient) INFRA_FAILURE=1 ;; esac
    emit_event fix_discovery_error attempt="$attempt" max_attempts="$FACTORY_GH_RETRIES" category="$category" error="$err_text"
    if ! should_retry_category "$category" || [[ "$attempt" -ge "$FACTORY_GH_RETRIES" ]]; then
      break
    fi
    sleep $((attempt*2))
  done
  if [[ -s "$fix_err" ]]; then
    cat "$fix_err" >&2
  fi
  rm -f "$fix_err"
  while IFS=$'\t' read -r pr_number issue_number head_sha reasons marker; do
    [[ -z "$pr_number" ]] && continue
    [[ "$fix_count" -ge "$MAX_FIX_SESSIONS" ]] && break
    if [[ "$(has_pr_marker "$pr_number" "$marker")" == "true" ]]; then
      log "PR #$pr_number already attempted for head $head_sha ($reasons); skipping"
      emit_event marker_skip pr="$pr_number" reason="already attempted"
      continue
    fi
    if [[ "$(has_marker "$issue_number" "$BUILD_MARKER")" == "true" ]]; then
      log "issue #$issue_number already built; skipping fix for PR #$pr_number"
      emit_event marker_skip issue="$issue_number" pr="$pr_number" reason="already built"
      continue
    fi
    claim_key="fix-${pr_number}-${head_sha}-${reasons}"
    claim_dir=""
    if [[ "$DRY_RUN" != 1 ]]; then
      if ! claim_dir="$(acquire_claim "$claim_key")"; then
        log "PR #$pr_number already claimed or claim conflict; skipping"
        emit_event claim_conflict pr="$pr_number" reason="${claim_dir:-claim-failed}"
        continue
      fi
    fi
    mapfile -t labels < <(issue_labels "$issue_number" 2>/dev/null || true)
    IFS=$'\t' read -r model backup_model < <(model_for_labels "${labels[@]}")
    emit_event fix_selected pr="$pr_number" issue="$issue_number" reasons="$reasons" model="${model:-}" backup_model="${backup_model:-}"
    if [[ "$DRY_RUN" == 1 ]]; then
      log "dry-run: would fix PR #$pr_number (issue #$issue_number, reasons: $reasons, model: ${model:-opencode default}, backup: ${backup_model:-none}, on-usage-filled: $ON_USAGE_FILLED)"
      emit_event dry_run kind="fix" pr="$pr_number" issue="$issue_number"
      fix_count=$((fix_count + 1))
    else
      if start_session "fix" "$pr_number" "factory: fix PR #$pr_number (issue #$issue_number)" "$model" "$backup_model" "$(fix_prompt "$pr_number" "$issue_number" "$reasons" "$marker")"; then
        :
      else
        fix_failures=$((fix_failures + 1))
      fi
      release_claim "$claim_dir"
      fix_count=$((fix_count + 1))
    fi
  done <<< "$fix_candidates_output"
  # fixes are serialized to avoid shared-worktree races; no background wait needed
  :
fi

# Build path, sub-path 2
build_issue=""
build_candidates_output=""
build_err="$(mktemp)"
for attempt in $(seq 1 "$FACTORY_GH_RETRIES"); do
  if build_candidates_output="$("$SCRIPT_DIR/discover_build_candidates.py" "$APPROVED_LABEL" 2>"$build_err")"; then
    break
  fi
  err_text="$(cat "$build_err" 2>/dev/null || true)"
  category="$(classify_gh_text "$err_text")"
  case "$category" in auth|permission|rate_limit|transient) INFRA_FAILURE=1 ;; esac
  emit_event build_discovery_error attempt="$attempt" max_attempts="$FACTORY_GH_RETRIES" category="$category" error="$err_text"
  if ! should_retry_category "$category" || [[ "$attempt" -ge "$FACTORY_GH_RETRIES" ]]; then
    break
  fi
  sleep $((attempt*2))
done
if [[ -s "$build_err" ]]; then
  if grep -q "project priority unavailable" "$build_err"; then
    emit_event project_priority_fallback error="$(cat "$build_err")"
  fi
  cat "$build_err" >&2
fi
rm -f "$build_err"

while IFS= read -r candidate; do
  [[ -z "$candidate" ]] && continue
  if [[ "$(has_marker "$candidate" "$BUILD_MARKER")" == "true" ]]; then
    log "issue #$candidate already built (marker present); skipping"
    emit_event marker_skip issue="$candidate" reason="already built"
    continue
  fi
  open_pr=""
  if ! open_pr="$(open_factory_pr_for_issue "$candidate")"; then
    log "could not determine open factory PR state for #$candidate; skipping candidate"
    emit_event marker_skip issue="$candidate" reason="open factory PR state unknown"
    continue
  fi
  if [[ -n "$open_pr" ]]; then
    log "issue #$candidate has an open factory PR; skipping new build"
    emit_event marker_skip issue="$candidate" reason="open factory PR"
    continue
  fi
  build_issue="$candidate"
  break
done <<< "$build_candidates_output"

if [[ -n "$build_issue" ]]; then
  emit_event build_selected issue="$build_issue"
fi

if [[ -z "$plan_issue" && "$fix_count" -eq 0 && -z "$build_issue" ]]; then
  if [[ "$INFRA_FAILURE" -eq 1 ]]; then
    log "discovery failed due to infrastructure/auth/rate-limit/transient issues; not reporting nothing_to_do"
    emit_event discovery_failed infra_failure=1
    emit_event tick_result result="failure" reason="discovery_failed"
    exit 1
  fi
  log "nothing to do"
  emit_event nothing_to_do
  exit 0
fi

if [[ -n "$plan_issue" ]]; then
  IFS=$'\t' read -r model backup_model < <(model_for_labels)
  emit_event plan_selected issue="$plan_issue" model="${model:-}" backup_model="${backup_model:-}"
  if [[ "$DRY_RUN" == 1 ]]; then
    log "dry-run: would plan issue #$plan_issue (model: ${model:-opencode default}, backup: ${backup_model:-none}, on-usage-filled: $ON_USAGE_FILLED)"
    emit_event dry_run kind="plan" issue="$plan_issue"
  else
    plan_claim=""
    if ! plan_claim="$(acquire_claim "plan-${plan_issue}")"; then
      log "issue #$plan_issue already claimed for planning; skipping"
      emit_event claim_conflict issue="$plan_issue" reason="${plan_claim:-claim-failed}" kind="plan"
    else
      start_session "plan" "$plan_issue" "factory: plan issue #$plan_issue" "$model" "$backup_model" "$(plan_prompt "$plan_issue")" || TICK_RC=1
      release_claim "$plan_claim"
    fi
  fi
fi

if [[ -n "$build_issue" ]]; then
  mapfile -t labels < <(issue_labels "$build_issue" 2>/dev/null || true)
  IFS=$'\t' read -r model backup_model < <(model_for_labels "${labels[@]}")
  if [[ "$DRY_RUN" == 1 ]]; then
    log "dry-run: would build issue #$build_issue (model: ${model:-opencode default}, backup: ${backup_model:-none}, on-usage-filled: $ON_USAGE_FILLED)"
    emit_event dry_run kind="build" issue="$build_issue"
  else
    build_claim=""
    if ! build_claim="$(acquire_claim "build-${build_issue}")"; then
      log "issue #$build_issue already claimed for build; skipping"
      emit_event claim_conflict issue="$build_issue" reason="${build_claim:-claim-failed}" kind="build"
    else
      start_session "build" "$build_issue" "factory: build issue #$build_issue" "$model" "$backup_model" "$(build_prompt "$build_issue")" || TICK_RC=1
      release_claim "$build_claim"
    fi
  fi
fi

if [[ "${fix_failures:-0}" -gt 0 ]]; then TICK_RC=1; fi
if [[ "${TICK_RC:-0}" -ne 0 ]]; then
  emit_event tick_result result="failure" fix_failures="$fix_failures"
  exit "$TICK_RC"
fi
emit_event tick_result result="ok" fix_failures="$fix_failures"
