CREATE TABLE IF NOT EXISTS sample_items (
  id         TEXT PRIMARY KEY,
  name       TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL
);
