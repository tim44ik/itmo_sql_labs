CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TABLE app_user (
  user_id    BIGSERIAL PRIMARY KEY,
  email      TEXT NOT NULL UNIQUE CHECK (position('@' in email) > 1),
  full_name  TEXT NOT NULL,
  role       TEXT NOT NULL DEFAULT 'employee'
             CHECK (role IN ('guest', 'employee', 'admin')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE room (
  room_id   BIGSERIAL PRIMARY KEY,
  code      TEXT NOT NULL UNIQUE,
  capacity  INT  NOT NULL CHECK (capacity > 0),
  is_active BOOLEAN NOT NULL DEFAULT true
);

CREATE TABLE booking (
  booking_id BIGSERIAL PRIMARY KEY,
  room_id    BIGINT NOT NULL REFERENCES room(room_id)     ON DELETE RESTRICT,
  user_id    BIGINT NOT NULL REFERENCES app_user(user_id) ON DELETE RESTRICT,
  time_range TSTZRANGE NOT NULL,
  status     TEXT NOT NULL DEFAULT 'active'
             CHECK (status IN ('active', 'cancelled', 'completed', 'no_show')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT booking_time_valid CHECK (lower(time_range) < upper(time_range))
);

ALTER TABLE booking
ADD CONSTRAINT booking_no_overlap
EXCLUDE USING gist (
  room_id WITH =,
  time_range WITH &&
) WHERE (status = 'active');

CREATE TABLE booking_event (
  event_id   BIGSERIAL PRIMARY KEY,
  booking_id BIGINT NOT NULL REFERENCES booking(booking_id) ON DELETE CASCADE,
  event_type TEXT NOT NULL
             CHECK (event_type IN ('created', 'cancelled', 'completed', 'no_show')),
  payload    JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX booking_event_booking_id_idx ON booking_event(booking_id);
CREATE INDEX booking_event_created_at_idx ON booking_event(created_at);
CREATE INDEX booking_event_payload_gin    ON booking_event USING gin(payload);
