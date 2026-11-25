CREATE TABLE IF NOT EXISTS bookings (
  id           UUID PRIMARY KEY,
  user_id      UUID NOT NULL,
  start        TIMESTAMPTZ NOT NULL,
  "end"        TIMESTAMPTZ NOT NULL,
  status       TEXT NOT NULL DEFAULT 'active',
  cancelled_by UUID,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  cancelled_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS bookings_overlap_idx ON bookings (start, "end");
