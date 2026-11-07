#!/usr/bin/env bash
#
# deploy-environment.sh — deploy one environment (default: qa) from its branch.
#
# Usage:
#   dev-ops/scripts/deploy-environment.sh [env] [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="$REPO_ROOT/dev-ops/environments.yaml"

ENV_NAME="qa"
DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    *) ENV_NAME="$arg" ;;
  esac
done

log() { printf '[deploy-%s] %s\n' "$ENV_NAME" "$*"; }
die() { printf '[deploy-%s] ERROR: %s\n' "$ENV_NAME" "$*" >&2; exit 1; }

command -v python3 >/dev/null || die "python3 is required"
[[ -f "$ENV_FILE" ]] || die "environments.yaml not found: $ENV_FILE"

read_env() {
  python3 - "$ENV_FILE" "$ENV_NAME" <<'PY'
import sys
path, env = sys.argv[1], sys.argv[2]
branch = None
port = None
found = False
in_env = False
with open(path) as f:
    for raw in f:
        line = raw.rstrip('\n')
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        indent = len(line) - len(line.lstrip())
        key = line.strip().split(':', 1)[0].strip() if ':' in line.strip() else ''
        if indent == 2:
            in_env = (key == env)
            if in_env:
                found = True
            continue
        if in_env and indent >= 4 and ':' in line.strip():
            k, v = line.strip().split(':', 1)
            k = k.strip()
            v = v.strip().strip('"').strip("'")
            if k == 'branch':
                branch = v
            elif k == 'port':
                port = v
        if in_env and indent < 2 and line.strip():
            in_env = False
if not found:
    raise SystemExit(f"environment not found: {env}")
if not branch or not port:
    raise SystemExit(f"branch/port missing for environment: {env}")
print(f"{branch}\t{port}")
PY
}

ENV_INFO="$(read_env)" || die "failed to read environment config"
BRANCH="$(printf '%s' "$ENV_INFO" | cut -f1)"
PORT="$(printf '%s' "$ENV_INFO" | cut -f2)"
[[ -n "$BRANCH" && -n "$PORT" ]] || die "invalid environment config"

DEPLOY_DIR="${DEPLOY_DIR:-/opt/booking-system-${ENV_NAME}}"

if [[ "$DRY_RUN" -eq 1 ]]; then
  log "env=$ENV_NAME branch=$BRANCH port=$PORT deploy_dir=$DEPLOY_DIR"
  log "compose=$DEPLOY_DIR/projects/sauna/docker-compose.yml"
  exit 0
fi

LOCK_FILE="/var/lock/booking-deploy-${ENV_NAME}.lock"
mkdir -p "$(dirname "$LOCK_FILE")" 2>/dev/null || true
exec 9>"$LOCK_FILE"
flock -x 9

if [[ ! -d "$DEPLOY_DIR/.git" ]]; then
  log "provisioning deploy checkout at $DEPLOY_DIR"
  INSTALL_DIR="$DEPLOY_DIR" bash "$REPO_ROOT/projects/sauna/setup.sh"
fi

[[ -d "$DEPLOY_DIR/.git" ]] || die "deploy checkout missing: $DEPLOY_DIR"

if [[ -n "$(git -C "$DEPLOY_DIR" status --porcelain)" ]]; then
  die "deploy checkout has unexpected local changes"
fi

log "fetching $BRANCH"
git -C "$DEPLOY_DIR" fetch --prune origin "$BRANCH"

if git -C "$DEPLOY_DIR" show-ref --verify --quiet "refs/heads/$BRANCH"; then
  git -C "$DEPLOY_DIR" checkout "$BRANCH"
else
  git -C "$DEPLOY_DIR" checkout -b "$BRANCH" "origin/$BRANCH"
fi
git -C "$DEPLOY_DIR" rebase "origin/$BRANCH"

DEPLOYED_SHA="$(git -C "$DEPLOY_DIR" rev-parse "origin/$BRANCH")"
log "deploying $DEPLOYED_SHA"

UPDATE_FILE="$DEPLOY_DIR/dev-ops/environments.yaml"

update_yaml() {
  local status="$1" sha="${2:-}" ts="${3:-}"
  python3 - "$UPDATE_FILE" "$ENV_NAME" "$status" "$sha" "$ts" <<'PY'
import sys
path, env, status, sha, ts = sys.argv[1:6]
with open(path) as f:
    lines = f.read().splitlines(keepends=True)

start = None
for i, l in enumerate(lines):
    if l.strip() == env + ":" and (len(l) - len(l.lstrip())) == 2:
        start = i
        break
if start is None:
    raise SystemExit(f"environment not found: {env}")

end = len(lines)
for j in range(start + 1, len(lines)):
    l = lines[j]
    if not l.strip() or l.lstrip().startswith('#'):
        continue
    indent = len(l) - len(l.lstrip())
    if indent <= 2:
        end = j
        break

block = lines[start + 1:end]
keys = {
    'last_deploy': (ts if ts else None),
    'last_deploy_commit': (sha if sha else None),
    'last_deploy_status': status,
}
new_block = []
seen = set()
for l in block:
    s = l.strip()
    if s and not s.startswith('#') and ':' in s:
        k = s.split(':', 1)[0].strip()
        if k in keys:
            val = keys[k]
            if val is None:
                new_block.append(f"    {k}: null\n")
            else:
                new_block.append(f'    {k}: "{val}"\n')
            seen.add(k)
            continue
    new_block.append(l)
for k in ('last_deploy', 'last_deploy_commit', 'last_deploy_status'):
    if k not in seen:
        val = keys[k]
        if val is None:
            new_block.append(f"    {k}: null\n")
        else:
            new_block.append(f'    {k}: "{val}"\n')

if new_block and not new_block[-1].endswith('\n'):
    new_block[-1] += '\n'

lines[start + 1:end] = new_block
with open(path, 'w') as f:
    f.writelines(lines)
PY
}

surface_failure() {
  local sha="$1" logtail="$2"
  local issue_number=""
  issue_number=$(gh issue list --state open --search 'in:title "QA deployment failed"' --json number --jq '.[0].number' 2>/dev/null || true)
  local body
  body="Deployment of \`main\` to QA failed.

Time (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)
Commit: ${sha:-unknown}

Log tail:
\`\`\`
${logtail}
\`\`\`"
  if [[ -z "$issue_number" ]]; then
    gh issue create --title "QA deployment failed" --label bug --label dev-ops --body "$body" >/dev/null 2>&1 || true
  else
    gh issue comment "$issue_number" --body "$body" >/dev/null 2>&1 || true
  fi
}

recover_issue() {
  local sha="$1"
  local issue_number=""
  issue_number=$(gh issue list --state open --search 'in:title "QA deployment failed"' --json number --jq '.[0].number' 2>/dev/null || true)
  if [[ -n "$issue_number" ]]; then
    gh issue comment "$issue_number" --body "Recovered in ${sha}." >/dev/null 2>&1 || true
    gh issue close "$issue_number" >/dev/null 2>&1 || true
  fi
}

COMPOSE_FILE="$DEPLOY_DIR/projects/sauna/docker-compose.yml"
export PORT="$PORT"
export COMPOSE_PROJECT_NAME="booking-${ENV_NAME}"

log "starting compose"
if ! docker compose -f "$COMPOSE_FILE" up -d --build --remove-orphans; then
  LOGTAIL="$(docker compose -f "$COMPOSE_FILE" logs --tail=100 2>&1 || true)"
  update_yaml "failed" "$DEPLOYED_SHA" ""
  surface_failure "$DEPLOYED_SHA" "$LOGTAIL"
  die "docker compose up failed"
fi

deadline=$((SECONDS + 120))
healthy=0
while [[ $SECONDS -lt $deadline ]]; do
  if curl -fsS "http://127.0.0.1:${PORT}/healthz" >/dev/null 2>&1; then
    healthy=1
    break
  fi
  sleep 2
done

if [[ "$healthy" -ne 1 ]]; then
  LOGTAIL="$(docker compose -f "$COMPOSE_FILE" ps 2>&1 || true)
$(docker compose -f "$COMPOSE_FILE" logs --tail=100 2>&1 || true)"
  update_yaml "failed" "$DEPLOYED_SHA" ""
  surface_failure "$DEPLOYED_SHA" "$LOGTAIL"
  die "health check failed on port ${PORT}"
fi

log "health check passed"

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
update_yaml "success" "$DEPLOYED_SHA" "$TS"

cd "$DEPLOY_DIR"
if ! git diff --quiet -- dev-ops/environments.yaml; then
  git add dev-ops/environments.yaml
  git commit -m "chore(dev-ops): record ${ENV_NAME} deploy ${DEPLOYED_SHA}" || true
  if ! git push origin "$BRANCH" 2>/dev/null; then
    log "WARNING: failed to push metadata update"
  fi
fi

recover_issue "$DEPLOYED_SHA"
log "deploy complete: $DEPLOYED_SHA"
