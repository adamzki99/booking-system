#!/usr/bin/env bash
#
# request-skills.sh — call for the addition of open-source skills to this repo.
#
# Reads dev-ops/skills.yaml, vendors each missing skill into .opencode/skills/,
# and (default mode) proposes the addition as a pull request.
#
# Usage:
#   dev-ops/scripts/request-skills.sh            # vendor + open a PR
#   dev-ops/scripts/request-skills.sh --local    # vendor only, no branch/PR
#
# Dependencies: git, python3 + PyYAML; gh (authenticated) for PR mode.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
CONFIG="${SKILLS_CONFIG:-$REPO_ROOT/dev-ops/skills.yaml}"
SKILLS_DIR="$REPO_ROOT/.opencode/skills"
BASE_BRANCH="${BASE_BRANCH:-main}"
MODE="pr"
[[ "${1:-}" == "--local" ]] && MODE="local"

log() { printf '[request-skills] %s\n' "$*"; }
die() { printf '[request-skills] ERROR: %s\n' "$*" >&2; exit 1; }

[[ -f "$CONFIG" ]] || die "config not found: $CONFIG"
command -v git >/dev/null || die "git is required"
command -v python3 >/dev/null || die "python3 is required"
python3 -c 'import yaml' 2>/dev/null || die "PyYAML is required (pip install pyyaml)"
if [[ "$MODE" == "pr" ]]; then
  command -v gh >/dev/null || die "gh is required for PR mode (or use --local)"
  git diff --cached --quiet || die "staged changes present; commit or stash first"
fi

# Emit "id<TAB>repo<TAB>path<TAB>ref" per skill entry.
read_config() {
  python3 - "$CONFIG" << 'PYEOF'
import sys, yaml
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f) or {}
for s in data.get("skills") or []:
    row = [str(s.get(k, "") or "") for k in ("id", "repo", "path", "ref")]
    if all(row[:3]):
        print("\t".join(row))
PYEOF
}

# Sparse-fetch one skill directory from a remote git repo.
fetch_skill() { # $1 repo, $2 path, $3 ref, $4 dest
  local repo="$1" path="$2" ref="$3" dest="$4" tmp
  tmp="$(mktemp -d)" || return 1
  git clone --quiet --filter=blob:none --no-checkout --depth 1 "$repo" "$tmp" || { rm -rf "$tmp"; return 1; }
  git -C "$tmp" sparse-checkout set --no-cone "$path" >/dev/null 2>&1 \
    || git -C "$tmp" sparse-checkout set "$path" >/dev/null || { rm -rf "$tmp"; return 1; }
  if [[ -n "$ref" ]]; then
    git -C "$tmp" fetch --quiet --depth 1 origin "$ref" || { rm -rf "$tmp"; return 1; }
    git -C "$tmp" checkout --quiet FETCH_HEAD || { rm -rf "$tmp"; return 1; }
  else
    git -C "$tmp" checkout --quiet || { rm -rf "$tmp"; return 1; }
  fi
  [[ -f "$tmp/$path/SKILL.md" ]] || { rm -rf "$tmp"; return 1; }
  mkdir -p "$dest" || { rm -rf "$tmp"; return 1; }
  cp -r "$tmp/$path/." "$dest/" || { rm -rf "$tmp"; return 1; }
  rm -rf "$tmp"
}

added=()
while IFS=$'\t' read -r id repo path ref; do
  [[ "$id" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || die "invalid skill id '$id' (use kebab-case)"
  dest="$SKILLS_DIR/$id"
  if [[ -d "$dest" ]]; then
    log "skip '$id' (already present)"
    continue
  fi
  log "fetching '$id' from $repo ($path${ref:+ @ $ref})"
  if fetch_skill "$repo" "$path" "$ref" "$dest"; then
    printf 'repo: %s\npath: %s\nref: %s\n' "$repo" "$path" "${ref:-default}" > "$dest/.source"
    added+=("$id")
  else
    rm -rf "$dest"
    log "WARNING: '$id' has no SKILL.md at $repo/$path — skipped"
  fi
done < <(read_config)

[[ ${#added[@]} -gt 0 ]] || { log "nothing new to add"; exit 0; }
log "vendored: ${added[*]}"

[[ "$MODE" == "local" ]] && exit 0

branch="skills/request-$(date +%Y%m%d-%H%M%S)"
git checkout -b "$branch"
git add "$SKILLS_DIR"
git commit --quiet -m "Add open source skills: ${added[*]}"
git push --quiet -u origin "$branch"

{
  echo "Vendored open-source skills into \`.opencode/skills/\` per \`dev-ops/skills.yaml\`:"
  echo
  for id in "${added[@]}"; do
    src="$(cat "$SKILLS_DIR/$id/.source")"
    echo "- **$id** — ${src//[$'\n']/, }"
  done
  echo
  echo "## Review checklist"
  echo "- [ ] Each skill's license permits vendoring; license/notice files are included where required"
  echo "- [ ] Skill content is trusted (skills are instructions loaded by factory agents)"
} | gh pr create --base "$BASE_BRANCH" --title "Add open source skills: ${added[*]}" --body-file -

log "PR opened for: ${added[*]}"
