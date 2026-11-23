CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TABLE app_user (
  user_id    BIGSERIAL   PRIMARY KEY,
  email      TEXT        NOT NULL UNIQUE
                         CHECK (position('@' in email) > 1),
  full_name  TEXT        NOT NULL,
  role       TEXT        NOT NULL DEFAULT 'employee'
                         CHECK (role IN ('guest', 'employee', 'admin')),
  manager_id BIGINT      REFERENCES app_user(user_id) ON DELETE SET NULL,
    -- ON DELETE SET NULL: при увольнении руководителя его подчинённые
    -- остаются в системе. RESTRICT заблокировал бы увольнение менеджера,
    -- CASCADE удалил бы подчинённых вместе с руководителем — недопустимо.
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT app_user_not_own_manager
    CHECK (manager_id IS NULL OR manager_id <> user_id)
);

CREATE INDEX app_user_manager_id_idx ON app_user(manager_id);

CREATE TABLE user_phone (
  user_id BIGINT NOT NULL REFERENCES app_user(user_id) ON DELETE CASCADE,
    -- ON DELETE CASCADE: телефон — многозначный атрибут пользователя,
    -- без пользователя не имеет смысла. Удаление пользователя логически
    -- удаляет его телефоны.
  phone   TEXT   NOT NULL,
  PRIMARY KEY (user_id, phone),
  CONSTRAINT user_phone_length CHECK (length(btrim(phone)) >= 5)
);

CREATE TABLE room (
  room_id   BIGSERIAL   PRIMARY KEY,
  code      TEXT        NOT NULL UNIQUE,
  capacity  INT         NOT NULL CHECK (capacity > 0),
  is_active BOOLEAN     NOT NULL DEFAULT true
);

CREATE TABLE amenity (
  amenity_id BIGSERIAL PRIMARY KEY,
  name       TEXT      NOT NULL UNIQUE
);

CREATE TABLE room_amenity (
  room_id    BIGINT NOT NULL REFERENCES room(room_id)       ON DELETE CASCADE,
    -- ON DELETE RESTRICT: бронь — история и потенциально финансовый
    -- документ. Удаление помещения сломало бы аудит и отчёты.
    -- Правильный способ вывести помещение — room.is_active = false.
  amenity_id BIGINT NOT NULL REFERENCES amenity(amenity_id) ON DELETE CASCADE,
    -- ON DELETE RESTRICT: удаление пользователя с бронью уничтожит
    -- историю. Учётные записи деактивируются, а не удаляются.
  quantity   INT    NOT NULL DEFAULT 1 CHECK (quantity > 0),
  PRIMARY KEY (room_id, amenity_id)
);

CREATE TABLE booking (
  booking_id BIGSERIAL   PRIMARY KEY,
  room_id    BIGINT      NOT NULL REFERENCES room(room_id)     ON DELETE RESTRICT,
    -- ON DELETE CASCADE: booking_event — слабая сущность, событие
    -- существует только как часть истории конкретной брони.
    -- Сиротских событий быть не должно. На практике booking защищён
    -- RESTRICT сверху, каскад срабатывает только при TRUNCATE ... CASCADE.
  user_id    BIGINT      NOT NULL REFERENCES app_user(user_id) ON DELETE RESTRICT,
  time_range TSTZRANGE   NOT NULL,
  status     TEXT        NOT NULL DEFAULT 'active'
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
  event_id   BIGSERIAL   PRIMARY KEY,
  booking_id BIGINT      NOT NULL REFERENCES booking(booking_id) ON DELETE CASCADE,
    -- ON DELETE CASCADE: booking_event — слабая сущность, событие
    -- существует только как часть истории конкретной брони.
    -- Сиротских событий быть не должно. На практике booking защищён
    -- RESTRICT сверху, каскад срабатывает только при TRUNCATE ... CASCADE.
  event_type TEXT        NOT NULL
                         CHECK (event_type IN ('created', 'cancelled', 'completed', 'no_show')),
  payload    JSONB       NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX booking_event_booking_id_idx ON booking_event(booking_id);
CREATE INDEX booking_event_created_at_idx ON booking_event(created_at);
CREATE INDEX booking_event_payload_gin    ON booking_event USING gin(payload);

COMMENT ON TABLE  app_user            IS 'Пользователи системы: guest, employee, admin. Рекурсивная связь manager_id → user_id';

COMMENT ON TABLE  user_phone          IS 'Телефоны пользователя (многозначный атрибут). PK (user_id, phone)';

COMMENT ON TABLE  room                IS 'Помещения коворкинга. Альтернативный ключ — code';

COMMENT ON TABLE  amenity             IS 'Справочник удобств и оборудования (телевизор, доска, видеосвязь)';

COMMENT ON TABLE  room_amenity        IS 'M:N: помещение ↔ удобство с количеством. PK (room_id, amenity_id)';

COMMENT ON TABLE  booking             IS 'Брони. Запрет пересечения активных броней одного помещения — EXCLUDE USING gist';

COMMENT ON TABLE  booking_event       IS 'Журнал событий брони. Идентифицируется через booking_id';