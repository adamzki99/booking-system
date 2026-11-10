# Strands Decider — persistent dev-ops service (Pilot 1)

Runs Strands Decider (`/v1/systemone`) as a **separate, persistent** Docker
Compose project so booking environments do not restart it.

## Bring up

```sh
docker compose -f dev-ops/decider/docker-compose.yml up -d
```

Logs:

```sh
docker compose -f dev-ops/decider/docker-compose.yml logs -f
```

Stop (keeps model cache volume):

```sh
docker compose -f dev-ops/decider/docker-compose.yml down
```

## Endpoint

- **Decider API:** `http://<host>:8090/v1/systemone`
- **Host port:** `8090` (override with `DECIDER_HOST_PORT`), container port `8000`.
- The port `8090` is distinct from QA (`8080`) and candidate (`8081+`) ports in
  `dev-ops/environments.yaml`.

## Model

- Default model: `StrandsAgents/strands-decider-2B-qwen3.5-v1-2610`
  (baked into the image built from `Dockerfile`; override by rebuilding with a
  different model).
- CPU-only. GPU not required for Pilot 1.
- Weights are downloaded from Hugging Face on first run into the
  `decider-model-cache` volume.

## Fallback behavior

The triage helper (`dev-ops/scripts/decider-triage.py`) is fail-open: if the
service is unreachable, times out, returns an error, or reports confidence below
the threshold (default `0.5`, override `DECIDER_CONFIDENCE_THRESHOLD`), it prints
a documented fallback object and exits `0`:

```json
{"labels": [], "confidence": 0.0, "model": null, "fallback": true, "reason": "service_unavailable_or_low_confidence"}
```

Factory planning must never block on the decider service.
