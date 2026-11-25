#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
SCRIPT="$SCRIPT_DIR/../dependabot-sweep.sh"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); }
fail() { echo "FAIL: $*" >&2; FAIL=$((FAIL + 1)); }
assert_eq() {
  local expected="$1" actual="$2" name="$3"
  if [[ "$expected" == "$actual" ]]; then pass; else fail "$name (expected=$expected actual=$actual)"; fi
}
assert_file_contains() {
  local path="$1" pattern="$2" name="$3"
  if grep -Fq -- "$pattern" "$path"; then pass; else fail "$name (missing: $pattern)"; fi
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Local repo that looks like the target clone.
remote="$tmp/remotes/owner/repo.git"
mkdir -p "$(dirname "$remote")"
git init --bare --quiet "$remote"
seed="$tmp/seed"
git init --quiet "$seed"
git -C "$seed" config user.name test
git -C "$seed" config user.email test@test
printf 'seed\n' > "$seed/file.txt"
git -C "$seed" add file.txt
git -C "$seed" commit --quiet -m init
git -C "$seed" branch -M main
git -C "$seed" remote add origin "$remote"
git -C "$seed" push --quiet -u origin main

clone="$tmp/repo"
git clone --quiet "$remote" "$clone"
git -C "$clone" config user.name test
git -C "$clone" config user.email test@test

stub="$tmp/bin"
mkdir -p "$stub"

cat > "$stub/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail
cmd="${1:-}"; shift || true
case "$cmd" in
  auth)
    [[ "${1:-}" == "status" ]] && exit 0
    exit 0
    ;;
  pr)
    sub="${1:-}"; shift || true
    if [[ "$sub" == "list" ]]; then
      cat "${GH_PR_LIST_JSON:?}"
      exit 0
    fi
    ;;
  repo)
    sub="${1:-}"; shift || true
    if [[ "$sub" == "view" ]]; then
      printf 'main\n'
      exit 0
    fi
    if [[ "$sub" == "clone" ]]; then
      # tests precreate clone; clone only if missing
      target="${2:-}"
      if [[ -n "$target" && ! -d "$target/.git" ]]; then
        git clone --quiet "$GH_SEED_REMOTE" "$target"
      fi
      exit 0
    fi
    ;;
esac
echo "unexpected gh call: $cmd $*" >&2
exit 1
GH
chmod +x "$stub/gh"

cat > "$stub/opencode" <<'OC'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "models" ]]; then
  printf 'opencode-go/kimi-k2.5\n'
  exit 0
fi
if [[ "${1:-}" == "run" ]]; then
  printf '%s\n' "$@" > "${OPENCODE_ARGS_FILE:?}"
  prompt="${@: -1}"
  printf '%s' "$prompt" > "${OPENCODE_PROMPT_FILE:?}"
  echo "SWEEP_RESULT: merged=0 escalated=0 skipped=0"
  exit 0
fi
echo "unexpected opencode call: $*" >&2
exit 1
OC
chmod +x "$stub/opencode"

common_env=(
  "PATH=$stub:$PATH"
  "GH_SEED_REMOTE=$remote"
  "REPO_SLUG=owner/repo"
  "REPO_DIR=$clone"
  "WORK_DIR=$tmp/work"
  "LOG_DIR=$tmp/logs"
  "PROMPT_FILE=$SCRIPT_DIR/../dependabot-sweep-prompt.md"
  "MODEL=opencode-go/kimi-k2.5"
  "AGENT="
  "AUTO_APPROVE=1"
  "RUN_TIMEOUT=5m"
)

# Case 1: no open Dependabot PRs exits before opencode run.
printf '' > "$tmp/pr-empty.json"
args_file="$tmp/args-empty.txt"
prompt_file="$tmp/prompt-empty.txt"
env "${common_env[@]}" \
  GH_PR_LIST_JSON="$tmp/pr-empty.json" \
  OPENCODE_ARGS_FILE="$args_file" \
  OPENCODE_PROMPT_FILE="$prompt_file" \
  "$SCRIPT" >"$tmp/no-pr.out" 2>&1
assert_eq "0" "$?" "no PRs exits 0"
if [[ ! -f "$args_file" ]]; then pass; else fail "opencode should not run when no PRs"; fi
assert_file_contains "$tmp/no-pr.out" "No open Dependabot PRs" "no PR log"

# Case 2: open PRs invoke opencode with prompt/config.
printf '#12, #7\n' > "$tmp/pr-list.json"
args_file="$tmp/args-run.txt"
prompt_file="$tmp/prompt-run.txt"
env "${common_env[@]}" \
  GH_PR_LIST_JSON="$tmp/pr-list.json" \
  OPENCODE_ARGS_FILE="$args_file" \
  OPENCODE_PROMPT_FILE="$prompt_file" \
  DRY_RUN=1 \
  AUTO_MERGE=0 \
  MAX_PRS=3 \
  "$SCRIPT" >"$tmp/run.out" 2>&1
assert_eq "0" "$?" "run exits 0"
assert_file_contains "$args_file" "run" "opencode run arg"
assert_file_contains "$args_file" "--model" "model arg"
assert_file_contains "$args_file" "opencode-go/kimi-k2.5" "model value"
assert_file_contains "$args_file" "--auto" "auto arg"
assert_file_contains "$prompt_file" "RUN CONFIG" "prompt has run config"
assert_file_contains "$prompt_file" "Repository: owner/repo" "prompt repo"
assert_file_contains "$prompt_file" "Open Dependabot PRs at start: #12, #7" "prompt PRs"
assert_file_contains "$prompt_file" "DRY_RUN: 1" "prompt dry run"
assert_file_contains "$prompt_file" "AUTO_MERGE: 0" "prompt auto merge"
assert_file_contains "$prompt_file" "MAX_PRS: 3" "prompt max prs"
assert_file_contains "$tmp/run.out" "SWEEP_RESULT: merged=0 escalated=0 skipped=0" "result logged"

echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
