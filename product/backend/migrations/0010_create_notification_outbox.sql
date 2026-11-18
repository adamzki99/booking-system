CREATE TABLE IF NOT EXISTS notification_outbox (
  id               BIGSERIAL PRIMARY KEY,
  event_id         BIGINT NOT NULL,
  kind             TEXT   NOT NULL,
  recipient_email  TEXT   NOT NULL,
  subject          TEXT   NOT NULL,
  body             TEXT   NOT NULL,
  status           TEXT   NOT NULL DEFAULT 'pending',
  attempts         INT    NOT NULL DEFAULT 0,
  next_attempt_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_error       TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  sent_at          TIMESTAMPTZ,
  UNIQUE (event_id, kind, recipient_email)
);
CREATE INDEX IF NOT EXISTS notification_outbox_due_idx
  ON notification_outbox (status, next_attempt_at);
