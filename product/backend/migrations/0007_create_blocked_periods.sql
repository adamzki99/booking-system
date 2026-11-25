CREATE TABLE IF NOT EXISTS blocked_periods (
  id         UUID PRIMARY KEY,
  start      TIMESTAMPTZ NOT NULL,
  "end"      TIMESTAMPTZ NOT NULL,
  blocked_by UUID NOT NULL,
  blocked_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX IF NOT EXISTS blocked_periods_overlap_idx ON blocked_periods (start, "end");
