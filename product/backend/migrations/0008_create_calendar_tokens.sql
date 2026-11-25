CREATE TABLE IF NOT EXISTS calendar_tokens (
  user_id    UUID PRIMARY KEY,
  token_hash TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
