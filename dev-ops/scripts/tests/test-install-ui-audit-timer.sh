#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
SCRIPT="$SCRIPT_DIR/../install-ui-audit-timer.sh"
PASS=0; FAIL=0
fail() { echo "FAIL: $*" >&2; FAIL=$((FAIL+1)); }
pass() { PASS=$((PASS+1)); }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

audit="$tmp/run-ui-audit.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$audit"
chmod +x "$audit"

units="$tmp/units"
"$SCRIPT" --env qa --timezone Europe/Stockholm --times 2 \
  --script "$audit" --unit-dir "$units" --no-enable >/dev/null
service="$units/booking-qa-ui-audit.service"
timer="$units/booking-qa-ui-audit.timer"
[[ -f "$service" ]] && pass || fail "service written"
[[ -f "$timer" ]] && pass || fail "timer written"
grep -q "ExecStart=$audit --env qa --local --no-issue-filing" "$service" && pass || fail "service ExecStart"
grep -q "^ExecStartPre=.*docker info" "$service" && pass || fail "service waits for Docker"
grep -qx 'TimeoutStartSec=120min' "$service" && pass || fail "service timeout"
grep -qx 'OnCalendar=\*-\*-\* 02:00:00 Europe/Stockholm' "$timer" && pass || fail "timer OnCalendar"
grep -qx 'Persistent=true' "$timer" && pass || fail "timer Persistent"
grep -qx 'AccuracySec=1min' "$timer" && pass || fail "timer accuracy"
grep -qx "Unit=booking-qa-ui-audit.service" "$timer" && pass || fail "timer Unit"
grep -qx "WantedBy=timers.target" "$timer" && pass || fail "timer install section"

# issue filing flag is reflected
units2="$tmp/units2"
"$SCRIPT" --env qa --script "$audit" --unit-dir "$units2" --issue-filing --no-enable >/dev/null
grep -q "ExecStart=$audit --env qa --local --issue-filing" "$units2/booking-qa-ui-audit.service" && pass || fail "issue filing flag"

# artifact root becomes environment variable
units3="$tmp/units3"
"$SCRIPT" --env qa --script "$audit" --unit-dir "$units3" --artifact-root /var/lib/ui-audit --no-enable >/dev/null
grep -qx 'Environment=UI_AUDIT_ARTIFACT_ROOT=/var/lib/ui-audit' "$units3/booking-qa-ui-audit.service" && pass || fail "artifact root env"

# idempotent
out="$("$SCRIPT" --env qa --timezone Europe/Stockholm --times 02 \
  --script "$audit" --unit-dir "$units" --no-enable)"
printf '%s\n' "$out" | grep -q "unchanged: $service" && pass || fail "service idempotent"
printf '%s\n' "$out" | grep -q "unchanged: $timer" && pass || fail "timer idempotent"

# dry run
dry_units="$tmp/dry-units"
out="$("$SCRIPT" --env qa --script "$audit" --unit-dir "$dry_units" --dry-run)"
[[ ! -e "$dry_units" ]] && pass || fail "dry run writes nothing"
printf '%s' "$out" | grep -q 'systemctl --user enable booking-qa-ui-audit.timer' && pass || fail "dry run enable"
printf '%s' "$out" | grep -q 'systemctl --user restart booking-qa-ui-audit.timer' && pass || fail "dry run restart"

# no-linger
out="$("$SCRIPT" --env qa --script "$audit" --unit-dir "$dry_units" --dry-run --no-linger)"
printf '%s' "$out" | grep -q 'loginctl enable-linger' && fail "no-linger prints linger" || pass

# invalid timezone rejected
set +e
"$SCRIPT" --env qa --timezone Not/AZone --script "$audit" --unit-dir "$units" --no-enable >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -ne 0 ]] && pass || fail "invalid timezone rejected"

# prod env rejected
set +e
"$SCRIPT" --env prod --script "$audit" --unit-dir "$units" --no-enable >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -ne 0 ]] && pass || fail "prod env rejected"

# missing script rejected
set +e
"$SCRIPT" --env qa --script "$tmp/missing.sh" --unit-dir "$units" --no-enable >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -ne 0 ]] && pass || fail "missing script rejected"

# systemd-analyze accepts expression when available
if command -v systemd-analyze >/dev/null 2>&1; then
  systemd-analyze calendar '*-*-* 02:00:00 Europe/Stockholm' >/dev/null \
    && pass || fail "systemd accepts OnCalendar"
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
