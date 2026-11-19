#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
SCRIPT="$SCRIPT_DIR/../install-deploy-timer.sh"
PASS=0; FAIL=0
fail() { echo "FAIL: $*" >&2; FAIL=$((FAIL+1)); }
pass() { PASS=$((PASS+1)); }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

deploy="$tmp/deploy-environment.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$deploy"
chmod +x "$deploy"

units="$tmp/units"
"$SCRIPT" --env qa --timezone Europe/Stockholm --times 0,12 \
  --script "$deploy" --unit-dir "$units" --no-enable >/dev/null
service="$units/booking-qa-deploy.service"
timer="$units/booking-qa-deploy.timer"
[[ -f "$service" ]] && pass || fail "service written"
[[ -f "$timer" ]] && pass || fail "timer written"
grep -qx "ExecStart=$deploy qa" "$service" && pass || fail "service ExecStart"
grep -qx 'OnCalendar=\*-\*-\* 00,12:00:00 Europe/Stockholm' "$timer" && pass || fail "timer OnCalendar"
grep -qx "Unit=booking-qa-deploy.service" "$timer" && pass || fail "timer Unit"
grep -qx "WantedBy=timers.target" "$timer" && pass || fail "timer install section"

# A second run is idempotent.
"$SCRIPT" --env qa --timezone Europe/Stockholm --times 00,12 \
  --script "$deploy" --unit-dir "$units" --no-enable >/dev/null
grep -qx "ExecStart=$deploy qa" "$service" && pass || fail "idempotent rerun"

# Dry run must not write anything.
dry_units="$tmp/dry-units"
out="$("$SCRIPT" --env qa --script "$deploy" --unit-dir "$dry_units" --dry-run)"
[[ ! -e "$dry_units" ]] && pass || fail "dry run writes nothing"
printf '%s' "$out" | grep -q 'systemctl --user enable --now booking-qa-deploy.timer' \
  && pass || fail "dry run prints activation command"

# Invalid timezone is rejected.
set +e
"$SCRIPT" --env qa --timezone Not/AZone --script "$deploy" --unit-dir "$units" --no-enable >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -ne 0 ]] && pass || fail "invalid timezone rejected"

# Invalid hour is rejected.
set +e
"$SCRIPT" --env qa --times 24 --script "$deploy" --unit-dir "$units" --no-enable >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -ne 0 ]] && pass || fail "invalid hour rejected"

# Missing deploy script is rejected.
set +e
"$SCRIPT" --env qa --script "$tmp/missing.sh" --unit-dir "$units" --no-enable >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -ne 0 ]] && pass || fail "missing script rejected"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
