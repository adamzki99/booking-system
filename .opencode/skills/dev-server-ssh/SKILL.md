---
name: dev-server-ssh
description: Use only when the user explicitly requests controlled SSH access to the development server for inspection, logs, service operations, or small reviewed hotfixes with human approval.
---

# Dev-server SSH

Use this skill only for an explicitly requested dev/QA operation. Never use it
for production. The entry point is
`dev-ops/scripts/dev-server-agent.sh`; it drives local `ssh`, keeps credentials
on the operator machine, reuses an SSH control connection, and appends JSONL
audit records.

## Prerequisites

1. Confirm that the operator has asked for dev-server access and stated the
   intended environment and outcome. Abort on ambiguity.
2. Ask the operator to populate the gitignored `dev-ops/.env` from
   `dev-ops/.env.example`, or provide equivalent environment variables. Never
   print or commit that file. Use `dev-ops/environments.yaml` for environment
   ports and `projects/<name>/` for deployment configuration.
3. Require a readable key (`DEV_SERVER_KEY`/`DEV_SERVER_KEY_PATH`, or a default
   SSH key). Password authentication is a fallback only: it requires
   `DEV_SERVER_PASSWORD`, `sshpass`, and separate interactive confirmation.
4. Validate locally without connecting:

   ```sh
   dev-ops/scripts/dev-server-agent.sh --self-check
   ```

## Human-in-the-loop protocol

1. Stay interactive. Never use OpenCode `--auto`, unattended approval, or a
   non-interactive factory tick for a mutation.
2. Before every remote command, show the operator the exact command, its
   classification, and its intended impact. Ask whenever the scope or effect is
   unclear; prefer many questions to an assumption.
3. Clearly read-only inspection may proceed through the wrapper and is logged.
   Examples include `uptime`, service status, logs, and `docker compose ps`.
   Unknown or complex shell is treated as impactful.
4. For every mutating, destructive, ambiguous, or otherwise impactful command,
   use `--impact` and require the human to answer the wrapper's controlling-TTY
   `y/N` prompt:

   ```sh
   dev-ops/scripts/dev-server-agent.sh \
     --command '<approved command>' \
     --impact '<specific intended impact>'
   ```

   Empty input or anything other than `y`/`yes` denies. Without a TTY, the
   command is not executed. Never answer the prompt yourself, feed it input, or
   use `expect`, `script`, or another mechanism to manufacture approval. If no
   human can approve, stop and ask the operator to run the command.
5. Use only this wrapper for remote operations. Do not invoke `ssh`, `scp`,
   `sftp`, or a remote shell directly, and do not ask the operator to bypass the
   wrapper. The wrapper is an approval/audit control, not a sandbox.
6. Do not put secrets in commands or impact text. Do not print env files,
   credentials, private keys, or tokens. The log redacts configured secrets, but
   that is not permission to expose them.

## Allowed operations

- Inspect service/container status, logs, Compose state, resource usage, and
  deployment configuration without exposing secret values.
- After explicit approval, restart dev/QA services and apply small,
  well-understood configuration fixes or hotfixes.
- Use the environment names and ports from `dev-ops/environments.yaml` and the
  Compose files under `projects/<name>/`.

## Prohibited operations

- Production access; destructive data changes; deleting database records,
  volumes, or other data; or bypassing the project's no-deletes/event policy.
- Editing secrets in place, exfiltrating credentials, disabling host-key
  checking, or committing hosts, credentials, keys, or logs.
- Bypassing review, tests, security checks, or the human approval gate.
- Leaving snowflake changes: reconcile every persistent server change into the
  repository through a reviewed pull request. Cancellations and state changes in
  the booking domain are events, not deletions.

## Auditing and follow-up

The default append-only log is
`${XDG_STATE_HOME:-~/.local/state}/booking-system/dev-server-agent.jsonl`.
It records timestamp, actor, target, redacted command, impact, and outcome; do
not commit it. Report what ran and its exit status. Reconcile changes through a
PR, then verify the dev/QA environment matches the reviewed repository state.
