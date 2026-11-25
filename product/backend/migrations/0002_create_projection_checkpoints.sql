CREATE TABLE IF NOT EXISTS projection_checkpoints (
  projection_name TEXT PRIMARY KEY,
  last_event_id   BIGINT NOT NULL,
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
