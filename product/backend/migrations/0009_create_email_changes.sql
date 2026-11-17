CREATE TABLE IF NOT EXISTS email_changes (
  user_id      UUID PRIMARY KEY,
  old_email    TEXT NOT NULL,
  new_email    TEXT NOT NULL,
  code_hash    TEXT NOT NULL,
  expires_at   TIMESTAMPTZ NOT NULL,
  requested_at TIMESTAMPTZ NOT NULL,
  confirmed_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS email_changes_new_email_idx ON email_changes (new_email);
