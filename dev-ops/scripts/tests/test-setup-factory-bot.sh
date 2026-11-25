#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd -P)"
SCRIPT="$SCRIPT_DIR/../../factory/setup-bot.sh"
PASS=0; FAIL=0
fail() { echo "FAIL: $*" >&2; FAIL=$((FAIL + 1)); }
pass() { PASS=$((PASS + 1)); }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
stubs="$tmp/bin"
mkdir -p "$stubs" "$tmp/home"
command_log="$tmp/commands.log"
export SETUP_CMD_LOG="$command_log"
: > "$command_log"

cat > "$stubs/python3" <<'SH'
#!/usr/bin/env bash
printf 'python3 %s\n' "$*" >> "$SETUP_CMD_LOG"
if [[ "${1:-}" == "-c" ]]; then
  exit 0
fi
if [[ "${1:-} ${2:-}" == "-m venv" ]]; then
  mkdir -p "$3/bin"
  cp "$0" "$3/bin/python"
  chmod +x "$3/bin/python"
  exit 0
fi
if [[ "${1:-} ${2:-}" == "-m pip" ]]; then
  exit 0
fi
if [[ "${1:-}" == *mint_github_app_token.py ]]; then
  if [[ "$*" == *"--print-app-slug"* ]]; then
    printf '%s\n' "${APP_SLUG:-booking-factory}"
  else
    printf 'test-installation-token\n'
  fi
  exit 0
fi
exit 1
SH

cat > "$stubs/gh" <<'SH'
#!/usr/bin/env bash
printf 'gh %s\n' "$*" >> "$SETUP_CMD_LOG"
if [[ "${1:-} ${2:-}" == "auth git-credential" ]]; then
  cat >/dev/null
  printf 'username=x-access-token\npassword=%s\n' "${GH_TOKEN:-}"
  exit 0
fi
if [[ "${1:-}" == "api" && "${2:-}" == users/* ]]; then
  if [[ "$*" == *".id"* ]]; then
    printf '123456\n'
    exit 0
  fi
  exit 1
fi
if [[ "${1:-}" == "api" && "${2:-}" == repos/* ]]; then
  [[ "${FAIL_REPO_LOOKUP:-0}" != 1 ]] || exit 1
  if [[ "${REPO_OWNER_IS_ORG:-0}" == 1 ]]; then
    printf 'Organization\n'
  else
    printf 'User\n'
  fi
  exit 0
fi
if [[ "${1:-} ${2:-}" == "repo view" ]]; then
  printf 'owner/repo\n'
  exit 0
fi
exit 1
SH

cat > "$stubs/opencode" <<'SH'
#!/usr/bin/env bash
printf 'opencode %s\n' "$*" >> "$SETUP_CMD_LOG"
exit 0
SH

cat > "$stubs/crontab" <<'SH'
#!/usr/bin/env bash
printf 'crontab %s\n' "$*" >> "$SETUP_CMD_LOG"
case "${1:-}" in
  -l)
    [[ -f "$CRONTAB_FILE" ]] || exit 1
    cat "$CRONTAB_FILE"
    ;;
  -)
    cat > "$CRONTAB_FILE"
    ;;
  *)
    exit 1
    ;;
esac
SH
chmod +x "$stubs"/*

key="$tmp/downloaded.pem"
printf '%s\n' '-----BEGIN RSA PRIVATE KEY-----' 'test-key-body' '-----END RSA PRIVATE KEY-----' > "$key"
chmod 600 "$key"

common_env=(
  "PATH=$stubs:$PATH"
  "PYTHON_BIN=$stubs/python3"
  "SETUP_CMD_LOG=$command_log"
  "XDG_CONFIG_HOME=$tmp/xdg-config"
  "XDG_DATA_HOME=$tmp/xdg-data"
  "XDG_STATE_HOME=$tmp/xdg-state"
)

run_setup() {
  env "${common_env[@]}" "$@"
}

config="$tmp/config dir"
venv="$tmp/xdg-data/booking-system-factory/venv"
state="$tmp/xdg-state/factory"
env_file="$config/factory.env"
wrapper="$config/run-tick.sh"
installed_key="$config/github-app.pem"
crontab_file="$tmp/crontab"
printf '%s\n' '17 2 * * * echo keep-existing-entry' > "$crontab_file"

out="$tmp/setup-output.log"
if run_setup CRONTAB_FILE="$crontab_file" "$SCRIPT" \
  --non-interactive \
  --app-id 123456 \
  --private-key "$key" \
  --repo owner/repo \
  --trusted-logins 'owner, second-user' \
  --schedule '15 * * * *' \
  --config-dir "$config" \
  --worktree "$tmp/factory-worktree" \
  --session-timeout 02700 \
  --container-mode 1 \
  --on-usage-filled skip \
  --max-fix-sessions 2 \
  --skip-dependencies \
  --skip-validation > "$out" 2>&1; then
  pass "interactive setup completes with supplied values"
else
  fail "setup failed"
  cat "$out" >&2
fi

[[ -f "$env_file" ]] && pass "environment file written" || fail "environment file missing"
[[ "$(stat -c %a "$env_file" 2>/dev/null || true)" == 600 ]] && pass "environment mode 0600" || fail "environment mode is not 0600"
[[ -f "$installed_key" ]] && pass "private key copied" || fail "private key missing"
[[ "$(stat -c %a "$installed_key" 2>/dev/null || true)" == 600 ]] && pass "private key mode 0600" || fail "private key mode is not 0600"
cmp -s "$key" "$installed_key" && pass "private key content preserved" || fail "private key content changed"
[[ -x "$wrapper" ]] && pass "cron wrapper executable" || fail "cron wrapper not executable"
[[ "$(stat -c %a "$wrapper" 2>/dev/null || true)" == 700 ]] && pass "cron wrapper mode 0700" || fail "cron wrapper mode is not 0700"
grep -Fq 'source ' "$wrapper" && grep -Fq 'factory.env' "$wrapper" \
  && pass "cron wrapper loads private environment" || fail "cron wrapper does not load environment"
grep -Fq 'exec ' "$wrapper" && grep -Fq 'tick.sh' "$wrapper" \
  && pass "cron wrapper executes tick" || fail "cron wrapper does not execute tick"
grep -Fq 'export FACTORY_LOGIN=' "$env_file" \
  && pass "environment exports factory settings to child processes" || fail "environment settings are not exported"
[[ -f "$state/tick.log" ]] && pass "tick log created" || fail "tick log missing"

set +e
(
  set -e
  set -a
  source "$env_file"
  set +a
  [[ "$FACTORY_GITHUB_APP_ID" == 123456 ]]
  [[ "$FACTORY_GITHUB_APP_PRIVATE_KEY_FILE" == "$installed_key" ]]
  [[ "$FACTORY_LOGIN" == 'booking-factory[bot]' ]]
  [[ "$FACTORY_TRUSTED_LOGINS" == 'owner,second-user' ]]
  [[ "$FACTORY_WORKTREE" == "$tmp/factory-worktree" ]]
  [[ "$FACTORY_SESSION_TIMEOUT" == 2700 ]]
  [[ "$FACTORY_CONTAINER_MODE" == 1 ]]
  [[ "$FACTORY_ON_USAGE_FILLED" == skip ]]
  [[ "$FACTORY_MAX_FIX_SESSIONS" == 2 ]]
  [[ "$FACTORY_LOG_SESSION_OUTPUT" == metadata ]]
  [[ "$GIT_AUTHOR_NAME" == 'booking-factory[bot]' ]]
  [[ "$GIT_AUTHOR_EMAIL" == '123456+booking-factory[bot]@users.noreply.github.com' ]]
  [[ "$GIT_COMMITTER_NAME" == "$GIT_AUTHOR_NAME" ]]
  [[ "$GIT_COMMITTER_EMAIL" == "$GIT_AUTHOR_EMAIL" ]]
  [[ "$GIT_TERMINAL_PROMPT" == 0 ]]
  [[ "$GIT_CONFIG_COUNT" == 3 ]]
  [[ "$GIT_CONFIG_KEY_0" == 'credential.https://github.com.helper' ]]
  [[ "$GIT_CONFIG_VALUE_0" == '!gh auth git-credential' ]]
  [[ "$GIT_CONFIG_KEY_1" == 'url.https://github.com/.insteadOf' ]]
  [[ "$GIT_CONFIG_VALUE_1" == 'git@github.com:' ]]
  [[ "$GIT_CONFIG_KEY_2" == 'url.https://github.com/.insteadOf' ]]
  [[ "$GIT_CONFIG_VALUE_2" == 'ssh://git@github.com/' ]]
  [[ "$PATH" == "$venv/bin:$HOME/.opencode/bin:"* ]]
  git_fixture="$tmp/git-fixture"
  git init -q "$git_fixture"
  git -C "$git_fixture" remote add origin git@github.com:example/project.git
  [[ "$(git -C "$git_fixture" ls-remote --get-url origin)" == 'https://github.com/example/project.git' ]]
  git -C "$git_fixture" remote set-url origin ssh://git@github.com/example/project.git
  [[ "$(git -C "$git_fixture" ls-remote --get-url origin)" == 'https://github.com/example/project.git' ]]
  [[ "$(git var GIT_AUTHOR_IDENT)" == 'booking-factory[bot] <123456+booking-factory[bot]@users.noreply.github.com> '* ]]
  credential="$(HOME="$tmp/home" GH_TOKEN=test-git-token git credential fill <<< $'protocol=https\nhost=github.com\n\n')"
  [[ "$credential" == *'password=test-git-token'* ]]
)
env_rc=$?
set -e
if [[ "$env_rc" -eq 0 ]]; then
  pass "environment configures bot identity, trust, Git, and factory settings"
else
  fail "generated environment has wrong values"
fi

if grep -Fq 'gh api user ' "$command_log"; then
  fail "setup used the unsupported installation-token /user endpoint"
else
  pass "setup avoids the unsupported installation-token /user endpoint"
fi
if grep -Fq 'test-installation-token' "$env_file" "$out"; then
  fail "installation token leaked"
else
  pass "installation token is not persisted or printed"
fi
if grep -Fq 'test-key-body' "$env_file" "$out"; then
  fail "private key content leaked"
else
  pass "private key content is not persisted in environment or output"
fi

grep -Fq '17 2 * * * echo keep-existing-entry' "$crontab_file" \
  && pass "existing cron entry preserved" || fail "existing cron entry lost"
grep -Fq '# >>> booking-system-factory >>>' "$crontab_file" \
  && pass "cron block written" || fail "cron block missing"
grep -Fq "# <<< booking-system-factory <<<" "$crontab_file" \
  && pass "cron block closed" || fail "cron block not closed"
grep -Fq "15 * * * * '$wrapper' >> '$state/tick.log' 2>&1" "$crontab_file" \
  && pass "cron schedule and quoted paths written" || fail "cron command wrong"

cp "$crontab_file" "$tmp/crontab.before"
if run_setup CRONTAB_FILE="$crontab_file" "$SCRIPT" \
  --non-interactive \
  --app-id 123456 \
  --repo owner/repo \
  --trusted-logins owner \
  --schedule '15 * * * *' \
  --config-dir "$config" \
  --worktree "$tmp/factory-worktree" \
  --skip-dependencies \
  --skip-validation > "$tmp/setup-second.log" 2>&1; then
  pass "setup rerun succeeds with existing key"
else
  fail "setup rerun failed"
  cat "$tmp/setup-second.log" >&2
fi
cmp -s "$crontab_file" "$tmp/crontab.before" \
  && pass "cron installation is idempotent" || fail "cron changed on rerun"

venv_config="$tmp/venv-config"
if run_setup CRONTAB_FILE="$tmp/venv-crontab" "$SCRIPT" \
  --non-interactive \
  --app-id 123456 \
  --private-key "$key" \
  --repo owner/repo \
  --trusted-logins owner \
  --config-dir "$venv_config" \
  --no-cron \
  --skip-validation > "$tmp/venv.log" 2>&1; then
  pass "setup creates dedicated Python environment"
else
  fail "venv setup failed"
  cat "$tmp/venv.log" >&2
fi
[[ -x "$venv/bin/python" ]] && pass "venv Python is executable" || fail "venv Python missing"
grep -Fq -- "-m pip install --disable-pip-version-check -r $REPO_ROOT/dev-ops/factory/requirements.txt" "$command_log" \
  && pass "venv installs factory requirements" || fail "venv requirements install not invoked"

fixture="$tmp/setup-fixture"
mkdir -p "$fixture/dev-ops/factory/lib"
cp "$SCRIPT" "$fixture/dev-ops/factory/setup-bot.sh"
cat > "$fixture/dev-ops/factory/tick.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ "${FACTORY_LOGIN:-}" == 'booking-factory[bot]' ]]
[[ "${FACTORY_TRUSTED_LOGINS:-}" == owner ]]
[[ "${GIT_AUTHOR_EMAIL:-}" == '123456+booking-factory[bot]@users.noreply.github.com' ]]
[[ "${GIT_CONFIG_VALUE_0:-}" == '!gh auth git-credential' ]]
printf 'called\n' > "$FAKE_TICK_MARKER"
exit "${FAKE_TICK_RC:-0}"
SH
chmod +x "$fixture/dev-ops/factory/tick.sh"

validated_marker="$tmp/validated-tick.marker"
validated_crontab="$tmp/validated-crontab"
if run_setup FAKE_TICK_MARKER="$validated_marker" CRONTAB_FILE="$validated_crontab" \
  "$fixture/dev-ops/factory/setup-bot.sh" \
  --non-interactive \
  --app-id 123456 \
  --private-key "$key" \
  --repo owner/repo \
  --trusted-logins owner \
  --config-dir "$tmp/validated-config" \
  --worktree "$tmp/validated-worktree" \
  --skip-dependencies > "$tmp/validated.log" 2>&1; then
  pass "setup validation succeeds with generated environment"
else
  fail "setup validation failed"
  cat "$tmp/validated.log" >&2
fi
[[ -f "$validated_marker" ]] && pass "tick dry run receives exported bot settings" || fail "tick dry run did not receive bot settings"
grep -Fq '# >>> booking-system-factory >>>' "$validated_crontab" \
  && pass "cron installed after successful validation" || fail "cron missing after successful validation"

failed_marker="$tmp/failed-tick.marker"
failed_crontab="$tmp/failed-validation-crontab"
set +e
run_setup FAKE_TICK_MARKER="$failed_marker" FAKE_TICK_RC=1 CRONTAB_FILE="$failed_crontab" \
  "$fixture/dev-ops/factory/setup-bot.sh" \
  --non-interactive \
  --app-id 123456 \
  --private-key "$key" \
  --repo owner/repo \
  --trusted-logins owner \
  --config-dir "$tmp/failed-validation-config" \
  --worktree "$tmp/failed-validation-worktree" \
  --skip-dependencies > "$tmp/failed-validation.log" 2>&1
rc=$?
set -e
[[ "$rc" -ne 0 ]] && pass "failed tick validation aborts setup" || fail "failed tick validation accepted"
[[ -f "$failed_marker" ]] && pass "failed validation invoked tick" || fail "failed validation did not invoke tick"
[[ ! -e "$failed_crontab" ]] && pass "failed validation does not install cron" || fail "cron installed after failed validation"

before_commands="$(wc -l < "$command_log")"
dry_config="$tmp/dry-config"
dry_crontab="$tmp/dry-crontab"
printf '%s\n' 'keep dry run crontab' > "$dry_crontab"
if run_setup CRONTAB_FILE="$dry_crontab" "$SCRIPT" \
  --non-interactive \
  --dry-run \
  --app-id 123456 \
  --private-key "$key" \
  --repo owner/repo \
  --trusted-logins owner \
  --schedule '30 * * * *' \
  --config-dir "$dry_config" \
  --worktree "$tmp/dry-worktree" > "$tmp/dry-output.log" 2>&1; then
  pass "dry run succeeds"
else
  fail "dry run failed"
  cat "$tmp/dry-output.log" >&2
fi
[[ ! -e "$dry_config" ]] && pass "dry run writes no config" || fail "dry run wrote config"
cmp -s "$dry_crontab" <(printf '%s\n' 'keep dry run crontab') \
  && pass "dry run leaves crontab unchanged" || fail "dry run changed crontab"
after_commands="$(wc -l < "$command_log")"
[[ "$before_commands" == "$after_commands" ]] \
  && pass "dry run makes no GitHub or crontab calls" || fail "dry run invoked external setup commands"
grep -Fq '30 * * * *' "$tmp/dry-output.log" \
  && pass "dry run prints requested schedule" || fail "dry run omitted schedule"

set +e
run_setup CRONTAB_FILE="$tmp/invalid-crontab" "$SCRIPT" \
  --non-interactive \
  --app-id 123456 \
  --private-key "$key" \
  --repo owner/repo \
  --trusted-logins owner \
  --schedule 'not a cron schedule' \
  --config-dir "$tmp/invalid-config" \
  --skip-dependencies \
  --skip-validation > "$tmp/invalid-schedule.log" 2>&1
rc=$?
set -e
[[ "$rc" -ne 0 ]] && pass "invalid schedule rejected" || fail "invalid schedule accepted"
[[ ! -e "$tmp/invalid-config" ]] && pass "invalid input writes nothing" || fail "invalid input wrote config"

set +e
run_setup "$SCRIPT" \
  --non-interactive \
  --app-id 123456 \
  --private-key "$key" \
  --repo owner/repo \
  --trusted-logins owner \
  --schedule $'0 * * * *\n* * * * * echo injected' \
  --config-dir "$tmp/multiline-config" \
  --skip-dependencies \
  --skip-validation > "$tmp/multiline.log" 2>&1
rc=$?
set -e
[[ "$rc" -ne 0 ]] && pass "multiline cron schedule rejected" || fail "multiline cron schedule accepted"
[[ ! -e "$tmp/multiline-config" ]] && pass "multiline schedule writes nothing" || fail "multiline schedule wrote config"

for timeout in 0 03600 04000 3301 3600; do
  set +e
  run_setup "$SCRIPT" \
    --non-interactive \
    --app-id 123456 \
    --private-key "$key" \
    --repo owner/repo \
    --trusted-logins owner \
    --session-timeout "$timeout" \
    --config-dir "$tmp/timeout-$timeout-config" \
    --skip-dependencies \
    --skip-validation > "$tmp/timeout-$timeout.log" 2>&1
  rc=$?
  set -e
  [[ "$rc" -ne 0 ]] && pass "unsafe session timeout $timeout rejected" || fail "unsafe session timeout $timeout accepted"
done

set +e
run_setup "$SCRIPT" \
  --non-interactive \
  --app-id 123456 \
  --private-key "$key" \
  --repo owner/repo \
  --trusted-logins owner \
  --worktree "$REPO_ROOT/nested-worktree" \
  --config-dir "$tmp/nested-worktree-config" \
  --skip-dependencies \
  --skip-validation > "$tmp/nested-worktree.log" 2>&1
rc=$?
set -e
[[ "$rc" -ne 0 ]] && pass "worktree inside primary checkout rejected" || fail "nested worktree accepted"
[[ ! -e "$tmp/nested-worktree-config" ]] && pass "nested worktree writes nothing" || fail "nested worktree wrote config"

ln -s "$REPO_ROOT" "$tmp/repo-link"
set +e
run_setup "$SCRIPT" \
  --non-interactive \
  --app-id 123456 \
  --private-key "$key" \
  --repo owner/repo \
  --trusted-logins owner \
  --config-dir "$tmp/repo-link/factory-config" \
  --skip-dependencies \
  --skip-validation > "$tmp/symlink-config.log" 2>&1
rc=$?
set -e
[[ "$rc" -ne 0 ]] && pass "symlinked config inside checkout rejected" || fail "symlinked config accepted"
[[ ! -e "$REPO_ROOT/factory-config" ]] && pass "symlinked config writes nothing" || fail "symlinked config wrote inside checkout"

set +e
run_setup APP_SLUG='bad slug' CRONTAB_FILE="$tmp/wrong-bot-crontab" "$SCRIPT" \
  --non-interactive \
  --app-id 123456 \
  --private-key "$key" \
  --repo owner/repo \
  --trusted-logins owner \
  --config-dir "$tmp/wrong-bot-config" \
  --skip-dependencies \
  --skip-validation > "$tmp/wrong-bot.log" 2>&1
rc=$?
set -e
[[ "$rc" -ne 0 ]] && pass "invalid GitHub App slug rejected" || fail "invalid App slug accepted"
[[ ! -e "$tmp/wrong-bot-crontab" ]] && pass "failed identity validation does not install cron" || fail "cron installed after identity failure"

set +e
run_setup REPO_OWNER_IS_ORG=1 CRONTAB_FILE="$tmp/org-crontab" "$SCRIPT" \
  --non-interactive \
  --app-id 123456 \
  --private-key "$key" \
  --repo owner/repo \
  --trusted-logins owner \
  --config-dir "$tmp/org-config" \
  --skip-dependencies \
  --skip-validation > "$tmp/org.log" 2>&1
rc=$?
set -e
[[ "$rc" -ne 0 ]] && pass "organization owner requires explicit human trusted logins" || fail "organization owner accepted as trusted human"
[[ ! -e "$tmp/org-crontab" ]] && pass "organization trust failure does not install cron" || fail "cron installed after trust failure"

set +e
run_setup FAIL_REPO_LOOKUP=1 CRONTAB_FILE="$tmp/repo-lookup-crontab" "$SCRIPT" \
  --non-interactive \
  --app-id 123456 \
  --private-key "$key" \
  --repo owner/repo \
  --trusted-logins owner \
  --config-dir "$tmp/repo-lookup-config" \
  --skip-dependencies \
  --skip-validation > "$tmp/repo-lookup.log" 2>&1
rc=$?
set -e
[[ "$rc" -ne 0 ]] && pass "repository owner lookup failure aborts setup" || fail "repository owner lookup failure accepted"
[[ ! -e "$tmp/repo-lookup-crontab" ]] && pass "owner lookup failure does not install cron" || fail "cron installed after owner lookup failure"

bad_key="$tmp/not-a-key.pem"
printf '%s\n' 'not a private key' > "$bad_key"
set +e
run_setup "$SCRIPT" \
  --non-interactive \
  --app-id 123456 \
  --private-key "$bad_key" \
  --repo owner/repo \
  --trusted-logins owner \
  --config-dir "$tmp/bad-key-config" \
  --skip-dependencies \
  --skip-validation > "$tmp/bad-key.log" 2>&1
rc=$?
set -e
[[ "$rc" -ne 0 ]] && pass "invalid private key rejected" || fail "invalid private key accepted"

no_cron_config="$tmp/no-cron-config"
no_cron_file="$tmp/no-cron-crontab"
printf '%s\n' 'keep no-cron entry' > "$no_cron_file"
if run_setup CRONTAB_FILE="$no_cron_file" "$SCRIPT" \
  --non-interactive \
  --app-id 123456 \
  --private-key "$key" \
  --repo owner/repo \
  --trusted-logins owner \
  --config-dir "$no_cron_config" \
  --no-cron \
  --skip-dependencies \
  --skip-validation > "$tmp/no-cron.log" 2>&1; then
  pass "no-cron setup succeeds"
else
  fail "no-cron setup failed"
  cat "$tmp/no-cron.log" >&2
fi
cmp -s "$no_cron_file" <(printf '%s\n' 'keep no-cron entry') \
  && pass "no-cron leaves crontab unchanged" || fail "no-cron changed crontab"

cp "$crontab_file" "$tmp/crontab.before-no-cron"
if run_setup CRONTAB_FILE="$crontab_file" "$SCRIPT" \
  --non-interactive \
  --app-id 123456 \
  --repo owner/repo \
  --trusted-logins owner \
  --schedule '15 * * * *' \
  --config-dir "$config" \
  --no-cron \
  --skip-dependencies \
  --skip-validation > "$tmp/no-cron-existing.log" 2>&1; then
  pass "no-cron rerun succeeds"
else
  fail "no-cron rerun failed"
  cat "$tmp/no-cron-existing.log" >&2
fi
cmp -s "$crontab_file" "$tmp/crontab.before-no-cron" \
  && pass "no-cron rerun preserves existing managed entry" || fail "no-cron rerun changed existing entry"
grep -Fq 'existing factory cron block was left unchanged' "$tmp/no-cron-existing.log" \
  && pass "no-cron rerun warns about existing managed entry" || fail "no-cron rerun did not warn"

fresh_cron_config="$tmp/fresh-cron-config"
fresh_crontab="$tmp/fresh-crontab"
if run_setup CRONTAB_FILE="$fresh_crontab" "$SCRIPT" \
  --non-interactive \
  --app-id 123456 \
  --private-key "$key" \
  --repo owner/repo \
  --trusted-logins owner \
  --schedule '45 * * * *' \
  --config-dir "$fresh_cron_config" \
  --skip-dependencies \
  --skip-validation > "$tmp/fresh-cron.log" 2>&1; then
  pass "setup works without an existing crontab"
else
  fail "setup without crontab failed"
  cat "$tmp/fresh-cron.log" >&2
fi
grep -Fq '45 * * * *' "$fresh_crontab" \
  && pass "fresh crontab receives factory schedule" || fail "fresh crontab missing factory schedule"

"$SCRIPT" --help > "$tmp/help.log"
grep -Fq -- '--schedule CRON' "$tmp/help.log" \
  && pass "help documents schedule input" || fail "help missing schedule option"

echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
