#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: dev-ops/scripts/monitoring.sh <factory|project-name> <up|down|status|logs|validate> [args...]

Commands:
  up        Start the monitoring stack (docker compose up -d)
  down      Stop the monitoring stack (volumes preserved unless --volumes)
  status    Show compose service status
  logs      Follow compose logs
  validate  Run the stack's validate script

Options:
  --volumes       With down: remove volumes after explicit confirmation
  -y, --yes       Confirm destructive volume removal (for non-interactive use)
  --env-file PATH Use a specific env file
  -h, --help      Show this help

Examples:
  dev-ops/scripts/monitoring.sh factory up
  dev-ops/scripts/monitoring.sh sauna status
  dev-ops/scripts/monitoring.sh sauna down --volumes
USAGE
}

die() { printf 'monitoring.sh: %s\n' "$*" >&2; exit 1; }

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [[ $# -lt 1 ]]; then usage; exit 1; fi
case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac

STACK="${1:-}"
shift
[[ $# -ge 1 ]] || { usage; exit 1; }
CMD="${1:-}"
shift

ENV_FILE=""
REMOVE_VOLUMES=0
CONFIRM_YES=0
PASS_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --volumes) REMOVE_VOLUMES=1; shift ;;
    -y|--yes) CONFIRM_YES=1; shift ;;
    --env-file) [[ $# -ge 2 ]] || die "--env-file requires a path"; ENV_FILE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) PASS_ARGS+=("$1"); shift ;;
  esac
done

case "$STACK" in
  factory)
    STACK_DIR="$REPO_ROOT/dev-ops/factory/monitoring"
    COMPOSE_FILE="$STACK_DIR/docker-compose.yml"
    DEFAULT_ENV="$STACK_DIR/.env"
    PROJECT_NAME="factory-monitoring"
    VALIDATE_CMD=("$STACK_DIR/scripts/validate.sh")
    ;;
  *)
    STACK_DIR="$REPO_ROOT/projects/$STACK/monitoring"
    COMPOSE_FILE="$STACK_DIR/compose.yaml"
    DEFAULT_ENV="$STACK_DIR/.env"
    PROJECT_NAME="${STACK}-monitoring"
    # Product/project instances use base validate plus instance compose config.
    VALIDATE_CMD=("$REPO_ROOT/product/monitoring/scripts/validate.sh")
    ;;
esac

[[ -d "$STACK_DIR" ]] || die "unknown monitoring stack: $STACK (expected dev-ops/factory/monitoring or projects/$STACK/monitoring)"
[[ -f "$COMPOSE_FILE" ]] || die "compose file not found: $COMPOSE_FILE"

if [[ -z "$ENV_FILE" ]]; then
  ENV_FILE="$DEFAULT_ENV"
fi

compose_cmd=(docker compose -f "$COMPOSE_FILE")
if [[ -f "$ENV_FILE" ]]; then
  compose_cmd+=(--env-file "$ENV_FILE")
fi
compose_cmd+=(-p "$PROJECT_NAME")

case "$CMD" in
  up)
    [[ -f "$ENV_FILE" ]] || die "missing env file: $ENV_FILE (copy .env.example to .env and fill required secrets)"
    exec "${compose_cmd[@]}" up -d "${PASS_ARGS[@]}"
    ;;
  status)
    exec "${compose_cmd[@]}" ps "${PASS_ARGS[@]}"
    ;;
  logs)
    exec "${compose_cmd[@]}" logs "${PASS_ARGS[@]}"
    ;;
  down)
    if [[ "$REMOVE_VOLUMES" -eq 1 ]]; then
      if [[ "$CONFIRM_YES" -ne 1 ]]; then
        if [[ ! -t 0 ]]; then
          die "refusing to remove volumes without confirmation; rerun with --volumes --yes in non-interactive mode only when intentional"
        fi
        printf 'This will remove volumes for %s. Type the stack name to confirm: ' "$PROJECT_NAME" >&2
        read -r confirm
        [[ "$confirm" == "$PROJECT_NAME" ]] || die "volume removal not confirmed"
      fi
      exec "${compose_cmd[@]}" down -v --remove-orphans "${PASS_ARGS[@]}"
    fi
    exec "${compose_cmd[@]}" down --remove-orphans "${PASS_ARGS[@]}"
    ;;
  validate)
    if [[ "$STACK" == "factory" ]]; then
      exec "${VALIDATE_CMD[@]}" "${PASS_ARGS[@]}"
    fi
    "${VALIDATE_CMD[@]}" "${PASS_ARGS[@]}"
    # Also validate the project instance compose config.
    if [[ -f "$ENV_FILE" ]]; then
      exec "${compose_cmd[@]}" config -q
    else
      die "missing env file: $ENV_FILE (required to validate project compose config)"
    fi
    ;;
  *)
    usage
    die "unknown command: $CMD"
    ;;
esac
