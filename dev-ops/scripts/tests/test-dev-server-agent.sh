#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
SCRIPT="$SCRIPT_DIR/../dev-server-agent.sh"
PASS=0
FAIL=0
fail() { echo "FAIL: $*" >&2; FAIL=$((FAIL + 1)); }
pass() { PASS=$((PASS + 1)); }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home" "$tmp/state"
: > "$tmp/id_ed25519"
chmod 600 "$tmp/id_ed25519"

cat > "$tmp/bin/ssh" <<'EOF'
#!/usr/bin/env bash
printf '%q ' "$@" >> "$SSH_CALL_LOG"
printf '\n' >> "$SSH_CALL_LOG"
case " $* " in
  *" -O "*) exit 1 ;;
  *" -N "*|*" -MNf "*) exit 0 ;;
  *" cat /tmp/example "*)
    printf 'remote-password=%s\n' "${DEV_SERVER_PASSWORD:-}"
    exit 0
    ;;
esac
printf 'remote-ok\n'
EOF
chmod +x "$tmp/bin/ssh"

cat > "$tmp/bin/opencode" <<'EOF'
#!/usr/bin/env bash
printf '%q ' "$@" >> "$OPENCODE_CALL_LOG"
for arg in "$@"; do
  [[ "$arg" != "--auto" ]] || printf 'AUTO_APPROVAL\n' >> "$OPENCODE_CALL_LOG"
done
printf '\nactor=%s\n' "${DEV_SERVER_ACTOR:-}" >> "$OPENCODE_CALL_LOG"
EOF
chmod +x "$tmp/bin/opencode"

cat > "$tmp/bin/sshpass" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == "-e" ]] || exit 2
shift
exec "$@"
EOF
chmod +x "$tmp/bin/sshpass"

base_env=(
  PATH="$tmp/bin:/usr/bin:/bin"
  HOME="$tmp/home"
  USER=tester
  XDG_STATE_HOME="$tmp/state"
  DEV_SERVER_HOST=test-host
  DEV_SERVER_KEY="$tmp/id_ed25519"
  DEV_SERVER_LOG_FILE="$tmp/actions.jsonl"
  SSH_CALL_LOG="$tmp/ssh-calls"
  OPENCODE_CALL_LOG="$tmp/opencode-calls"
)

# Self-check resolves safe defaults without connecting.
set +e
out="$(env -i "${base_env[@]}" "$SCRIPT" --self-check 2>&1)"
rc=$?
set -e
if [[ $rc -eq 0 && "$out" == *"port=22"* && "$out" == *"auth=key"* && ! -e "$tmp/ssh-calls" ]]; then
  pass
else
  fail "self-check (rc=$rc, output=$out)"
fi

# Clearly read-only commands run without a prompt and emit an audit record.
set +e
out="$(env -i "${base_env[@]}" "$SCRIPT" --command uptime 2>"$tmp/read-only.err")"
rc=$?
set -e
if [[ $rc -eq 0 && "$out" == *"remote-ok"* ]] \
  && grep -q 'uptime' "$tmp/ssh-calls" \
  && grep -q '"outcome": "succeeded"' "$tmp/actions.jsonl"; then
  pass
else
  fail "read-only command (rc=$rc, output=$out)"
fi

# Configured secrets are redacted from captured remote output as well as logs.
set +e
out="$(env -i "${base_env[@]}" DEV_SERVER_PASSWORD=remote-output-secret \
  "$SCRIPT" --command 'cat /tmp/example' 2>"$tmp/redaction.err")"
rc=$?
set -e
if [[ $rc -eq 0 && "$out" == *"[REDACTED]"* && "$out" != *"remote-output-secret"* ]] \
  && ! grep -q 'remote-output-secret' "$tmp/actions.jsonl"; then
  pass
else
  fail "remote output redaction (rc=$rc, output=$out)"
fi

# Compose inspection with global options remains read-only and non-interactive.
set +e
out="$(env -i "${base_env[@]}" "$SCRIPT" --command \
  'docker compose -f /tmp/compose.yml -p booking-qa ps' 2>"$tmp/compose.err")"
rc=$?
set -e
if [[ $rc -eq 0 && "$out" == *"remote-ok"* ]]; then
  pass
else
  fail "read-only compose inspection (rc=$rc, output=$out)"
fi

# An optional exact allow-list restricts commands without pre-approving them.
cp "$tmp/ssh-calls" "$tmp/ssh-calls.before-allow-list"
set +e
env -i "${base_env[@]}" DEV_SERVER_ALLOWED_COMMANDS=uptime \
  "$SCRIPT" --command 'docker compose ps' >"$tmp/allow-list.out" 2>"$tmp/allow-list.err"
rc=$?
set -e
if [[ $rc -ne 0 ]] && cmp -s "$tmp/ssh-calls" "$tmp/ssh-calls.before-allow-list"; then
  pass
else
  fail "exact command allow-list (rc=$rc)"
fi

# Disguised or explicit mutations remain denied without interactive approval.
deny_all=1
for command in \
  'uptime; touch /tmp/not-allowed' \
  'docker compose up -d' \
  'journalctl --vacuum-size=1G' \
  'find /tmp -delete' \
  "find /tmp '-delete'" \
  'hostname new-name'; do
  cp "$tmp/ssh-calls" "$tmp/ssh-calls.before-classifier"
  set +e
  env -i "${base_env[@]}" "$SCRIPT" --command "$command" \
    >"$tmp/classifier.out" 2>"$tmp/classifier.err"
  rc=$?
  set -e
  if [[ $rc -eq 0 ]] || ! cmp -s "$tmp/ssh-calls" "$tmp/ssh-calls.before-classifier"; then
    deny_all=0
    fail "classifier did not deny without approval: $command"
  fi
done
[[ "$deny_all" -eq 0 ]] || pass

# A human can explicitly approve an impactful command through a real TTY.
approval_command=(env -i "${base_env[@]}" "$SCRIPT" --command \
  'touch /tmp/dev-server-agent-test' --impact 'Tests explicit human approval')
printf -v approval_shell '%q ' "${approval_command[@]}"
set +e
printf 'y\n' | script -qec "$approval_shell" /dev/null >"$tmp/approval.out" 2>"$tmp/approval.err"
rc=$?
set -e
if [[ $rc -eq 0 ]] && grep -q 'touch.*dev-server-agent-test' "$tmp/ssh-calls" \
  && grep -q '"outcome": "approved"' "$tmp/actions.jsonl"; then
  pass
else
  fail "TTY approval (rc=$rc, output=$(cat "$tmp/approval.out"), calls=$(tail -n 2 "$tmp/ssh-calls"))"
fi

# Secrets embedded in commands are denied before the prompt can display them.
cp "$tmp/ssh-calls" "$tmp/ssh-calls.before-secret-prompt"
secret_command=(env -i "${base_env[@]}" DEV_SERVER_PASSWORD=tty-secret \
  "$SCRIPT" --command 'printf tty-secret' --impact 'Must not be displayed')
printf -v secret_shell '%q ' "${secret_command[@]}"
set +e
printf 'y\n' | script -qec "$secret_shell" /dev/null >"$tmp/secret-prompt.out" 2>"$tmp/secret-prompt.err"
rc=$?
set -e
if [[ $rc -ne 0 ]] && cmp -s "$tmp/ssh-calls" "$tmp/ssh-calls.before-secret-prompt" \
  && ! grep -q 'tty-secret' "$tmp/secret-prompt.out" \
  && ! grep -q 'tty-secret' "$tmp/actions.jsonl"; then
  pass
else
  fail "secret prompt rejection (rc=$rc)"
fi

# Password authentication also fails closed when confirmation is unavailable.
password_env=()
for entry in "${base_env[@]}"; do
  [[ "$entry" == DEV_SERVER_KEY=* ]] || password_env+=("$entry")
done
cp "$tmp/ssh-calls" "$tmp/ssh-calls.before-password"
set +e
env -i "${password_env[@]}" DEV_SERVER_PASSWORD=password-secret \
  "$SCRIPT" --command uptime >"$tmp/password.out" 2>"$tmp/password.err"
rc=$?
set -e
if [[ $rc -ne 0 ]] && cmp -s "$tmp/ssh-calls" "$tmp/ssh-calls.before-password"; then
  pass
else
  fail "password authentication confirmation (rc=$rc)"
fi

# Agent mode refuses to connect when no interactive terminal is available.
set +e
env -i "${base_env[@]}" "$SCRIPT" >"$tmp/agent-no-tty.out" 2>"$tmp/agent-no-tty.err"
rc=$?
set -e
if [[ $rc -ne 0 && ! -e "$tmp/opencode-calls" ]]; then
  pass
else
  fail "non-TTY agent rejection (rc=$rc)"
fi

# Agent mode starts interactive OpenCode without unattended auto-approval.
agent_command=(env -i "${base_env[@]}" "$SCRIPT")
printf -v agent_shell '%q ' "${agent_command[@]}"
set +e
script -qec "$agent_shell" /dev/null </dev/null >"$tmp/agent.out" 2>"$tmp/agent.err"
rc=$?
set -e
if [[ $rc -eq 0 ]] && grep -q -- '--prompt' "$tmp/opencode-calls" \
  && grep -q 'dev-server-ssh' "$tmp/opencode-calls" \
  && ! grep -q '^AUTO_APPROVAL$' "$tmp/opencode-calls" \
  && grep -q 'actor=tester/opencode' "$tmp/opencode-calls"; then
  pass
else
  fail "interactive OpenCode launch (rc=$rc, calls=$(cat "$tmp/opencode-calls" 2>/dev/null))"
fi

# Impactful commands fail closed without a TTY and never reach SSH or leak secrets.
cp "$tmp/ssh-calls" "$tmp/ssh-calls.before-deny"
set +e
env -i "${base_env[@]}" DEV_SERVER_PASSWORD=do-not-log-this \
  "$SCRIPT" --command 'echo do-not-log-this > /tmp/state' --impact 'Changes remote state' \
  >"$tmp/deny.out" 2>"$tmp/deny.err"
rc=$?
set -e
if [[ $rc -ne 0 ]] && cmp -s "$tmp/ssh-calls" "$tmp/ssh-calls.before-deny" \
  && grep -q '"outcome": "denied"' "$tmp/actions.jsonl" \
  && ! grep -q 'do-not-log-this' "$tmp/actions.jsonl"; then
  pass
else
  fail "non-TTY mutation denial or secret redaction (rc=$rc)"
fi

echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
