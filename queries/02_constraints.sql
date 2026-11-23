-- queries/02_constraints.sql (compact)
-- Негативные тесты — одна таблица VALUES + цикл.
-- Позитив для DEFAULT и ON DELETE — один DO-блок.
-- Проверяется и факт ошибки, и её SQLSTATE.
\set ON_ERROR_STOP on

TRUNCATE booking_event, booking, user_phone, room_amenity, amenity, room, app_user RESTART IDENTITY CASCADE;

-- 1. Позитивная база (используется негативными тестами)
INSERT INTO app_user (email, full_name, role) VALUES
  ('a@example.com', 'Alice', 'employee'),
  ('b@example.com', 'Bob',   'admin');
INSERT INTO user_phone (user_id, phone)
  SELECT user_id, '+70000000001' FROM app_user WHERE email='a@example.com';
INSERT INTO room (code, capacity) VALUES ('A101', 4), ('A102', 6);
INSERT INTO amenity (name) VALUES ('проектор');
INSERT INTO room_amenity (room_id, amenity_id)
  SELECT r.room_id, a.amenity_id FROM room r, amenity a WHERE r.code='A101' AND a.name='проектор';
INSERT INTO booking (room_id, user_id, time_range)
  SELECT r.room_id, u.user_id, tstzrange('2030-01-01 10:00+00','2030-01-01 11:00+00','[)')
  FROM room r, app_user u WHERE r.code='A101' AND u.email='a@example.com';
INSERT INTO booking_event (booking_id, event_type)
  SELECT booking_id, 'created' FROM booking LIMIT 1;

-- 2. Негативные тесты: (label, sql, ожидаемый SQLSTATE)
DO $$
DECLARE r record; ok bool;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      -- app_user
      ('app_user PK user_id',          $s$INSERT INTO app_user (user_id,email,full_name) VALUES (1,'d@x.com','D')$s$, '23505'),
      ('app_user UNIQUE email',        $s$INSERT INTO app_user (email,full_name) VALUES ('a@example.com','X')$s$, '23505'),
      ('app_user CHECK email @',       $s$INSERT INTO app_user (email,full_name) VALUES ('no-at-sign','X')$s$, '23514'),
      ('app_user CHECK role',          $s$INSERT INTO app_user (email,full_name,role) VALUES ('r@x.com','X','superadmin')$s$, '23514'),
      ('app_user NOT NULL email',      $s$INSERT INTO app_user (full_name) VALUES ('X')$s$, '23502'),
      ('app_user NOT NULL full_name',  $s$INSERT INTO app_user (email) VALUES ('n@x.com')$s$, '23502'),
      ('app_user CHECK self manager',  $s$UPDATE app_user SET manager_id=user_id WHERE email='a@example.com'$s$, '23514'),
      ('app_user FK manager_id',       $s$UPDATE app_user SET manager_id=999999 WHERE email='a@example.com'$s$, '23503'),
      -- user_phone
      ('user_phone PK (uid,phone)',    $s$INSERT INTO user_phone (user_id,phone) SELECT user_id,'+70000000001' FROM app_user WHERE email='a@example.com'$s$, '23505'),
      ('user_phone CHECK length>=5',   $s$INSERT INTO user_phone (user_id,phone) SELECT user_id,'123' FROM app_user WHERE email='a@example.com'$s$, '23514'),
      ('user_phone FK user_id',        $s$INSERT INTO user_phone (user_id,phone) VALUES (999999,'+7999')$s$, '23503'),
      -- room
      ('room PK room_id',              $s$INSERT INTO room (room_id,code,capacity) VALUES (1,'X1',4)$s$, '23505'),
      ('room UNIQUE code',             $s$INSERT INTO room (code,capacity) VALUES ('A101',8)$s$, '23505'),
      ('room CHECK capacity>0',        $s$INSERT INTO room (code,capacity) VALUES ('B1',0)$s$, '23514'),
      ('room NOT NULL code',           $s$INSERT INTO room (capacity) VALUES (2)$s$, '23502'),
      -- amenity
      ('amenity PK amenity_id',        $s$INSERT INTO amenity (amenity_id,name) VALUES (1,'доска')$s$, '23505'),
      ('amenity UNIQUE name',          $s$INSERT INTO amenity (name) VALUES ('проектор')$s$, '23505'),
      -- room_amenity
      ('room_amenity PK',              $s$INSERT INTO room_amenity (room_id,amenity_id) SELECT r.room_id,a.amenity_id FROM room r,amenity a WHERE r.code='A101' AND a.name='проектор'$s$, '23505'),
      ('room_amenity CHECK qty>0',     $s$INSERT INTO room_amenity (room_id,amenity_id,quantity) SELECT r.room_id,a.amenity_id,0 FROM room r,amenity a WHERE r.code='A102' AND a.name='проектор'$s$, '23514'),
      ('room_amenity FK room_id',      $s$INSERT INTO room_amenity (room_id,amenity_id) SELECT 999999,amenity_id FROM amenity WHERE name='проектор'$s$, '23503'),
      ('room_amenity FK amenity_id',   $s$INSERT INTO room_amenity (room_id,amenity_id) SELECT room_id,999999 FROM room WHERE code='A102'$s$, '23503'),
      -- booking
      ('booking PK booking_id',        $s$INSERT INTO booking (booking_id,room_id,user_id,time_range) SELECT 1,r.room_id,u.user_id,tstzrange('2030-01-05 10:00+00','2030-01-05 11:00+00','[)') FROM room r,app_user u WHERE r.code='A101' AND u.email='a@example.com'$s$, '23505'),
      ('booking CHECK time_valid',     $s$INSERT INTO booking (room_id,user_id,time_range) SELECT r.room_id,u.user_id,tstzrange('2030-02-01 10:00+00','2030-02-01 10:00+00','[]') FROM room r,app_user u WHERE r.code='A101' AND u.email='a@example.com'$s$, '23514'),
      ('booking CHECK status',         $s$INSERT INTO booking (room_id,user_id,time_range,status) SELECT r.room_id,u.user_id,tstzrange('2030-03-01 10:00+00','2030-03-01 11:00+00','[)'),'pending' FROM room r,app_user u WHERE r.code='A101' AND u.email='a@example.com'$s$, '23514'),
      ('booking FK room_id',           $s$INSERT INTO booking (room_id,user_id,time_range) SELECT 999999,user_id,tstzrange('2030-03-05 10:00+00','2030-03-05 11:00+00','[)') FROM app_user WHERE email='a@example.com'$s$, '23503'),
      ('booking FK user_id',           $s$INSERT INTO booking (room_id,user_id,time_range) SELECT room_id,999999,tstzrange('2030-03-06 10:00+00','2030-03-06 11:00+00','[)') FROM room WHERE code='A101'$s$, '23503'),
      ('booking EXCLUDE no_overlap',   $s$INSERT INTO booking (room_id,user_id,time_range) SELECT r.room_id,u.user_id,tstzrange('2030-01-01 10:30+00','2030-01-01 11:30+00','[)') FROM room r,app_user u WHERE r.code='A101' AND u.email='a@example.com'$s$, '23P01'),
      ('booking FK room RESTRICT',     $s$DELETE FROM room WHERE code='A101'$s$, '23503'),
      ('booking FK user RESTRICT',     $s$DELETE FROM app_user WHERE email='a@example.com'$s$, '23503'),
      -- booking_event
      ('booking_event PK event_id',    $s$INSERT INTO booking_event (event_id,booking_id,event_type) SELECT 1,booking_id,'cancelled' FROM booking LIMIT 1$s$, '23505'),
      ('booking_event FK booking_id',  $s$INSERT INTO booking_event (booking_id,event_type) VALUES (999999,'created')$s$, '23503'),
      ('booking_event CHECK type',     $s$INSERT INTO booking_event (booking_id,event_type) SELECT booking_id,'unknown' FROM booking LIMIT 1$s$, '23514')
    ) AS t(label, sql, sqlstate)
  LOOP
    ok := false;
    BEGIN
      EXECUTE r.sql;
    EXCEPTION WHEN OTHERS THEN
      ok := true;
      IF SQLSTATE <> r.sqlstate THEN
        RAISE EXCEPTION 'FAIL [%]: ждали SQLSTATE %, пришёл % (%)', r.label, r.sqlstate, SQLSTATE, SQLERRM;
      END IF;
      RAISE NOTICE 'OK [%] %', r.label, SQLSTATE;
    END;
    IF NOT ok THEN
      RAISE EXCEPTION 'FAIL [%]: ждали %, запрос прошёл', r.label, r.sqlstate;
    END IF;
  END LOOP;
END $$;

-- 3. Позитив: DEFAULT и ON DELETE
DO $$
DECLARE
  v_role text; v_active bool; v_qty int; v_status text; v_payload jsonb;
  v_created timestamptz; v_mgr bigint; v_cnt int;
BEGIN
  -- DEFAULT
  SELECT role INTO v_role FROM app_user WHERE email='a@example.com';
  IF v_role<>'employee' THEN RAISE EXCEPTION 'FAIL app_user.role DEFAULT: %', v_role; END IF;
  RAISE NOTICE 'OK [app_user.role DEFAULT=employee]';

  SELECT is_active INTO v_active FROM room WHERE code='A101';
  IF v_active IS NOT TRUE THEN RAISE EXCEPTION 'FAIL room.is_active DEFAULT: %', v_active; END IF;
  RAISE NOTICE 'OK [room.is_active DEFAULT=true]';

  SELECT ra.quantity INTO v_qty FROM room_amenity ra
    JOIN room r ON r.room_id=ra.room_id JOIN amenity a ON a.amenity_id=ra.amenity_id
    WHERE r.code='A101' AND a.name='проектор';
  IF v_qty<>1 THEN RAISE EXCEPTION 'FAIL room_amenity.quantity DEFAULT: %', v_qty; END IF;
  RAISE NOTICE 'OK [room_amenity.quantity DEFAULT=1]';

  SELECT status, created_at INTO v_status, v_created FROM booking LIMIT 1;
  IF v_status<>'active' THEN RAISE EXCEPTION 'FAIL booking.status DEFAULT: %', v_status; END IF;
  IF v_created IS NULL THEN RAISE EXCEPTION 'FAIL booking.created_at DEFAULT'; END IF;
  RAISE NOTICE 'OK [booking.status DEFAULT=active, created_at=now()]';

  SELECT payload, created_at INTO v_payload, v_created FROM booking_event LIMIT 1;
  IF v_payload IS DISTINCT FROM '{}'::jsonb THEN RAISE EXCEPTION 'FAIL booking_event.payload DEFAULT: %', v_payload; END IF;
  IF v_created IS NULL THEN RAISE EXCEPTION 'FAIL booking_event.created_at DEFAULT'; END IF;
  RAISE NOTICE 'OK [booking_event.payload DEFAULT={}, created_at=now()]';

  -- ON DELETE CASCADE: user_phone
  INSERT INTO app_user (email,full_name) VALUES ('tmp@x.com','Tmp');
  INSERT INTO user_phone (user_id,phone) SELECT user_id,'+70000000099' FROM app_user WHERE email='tmp@x.com';
  DELETE FROM app_user WHERE email='tmp@x.com';
  SELECT count(*) INTO v_cnt FROM user_phone WHERE phone='+70000000099';
  IF v_cnt>0 THEN RAISE EXCEPTION 'FAIL ON DELETE CASCADE user_phone: %', v_cnt; END IF;
  RAISE NOTICE 'OK [user_phone ON DELETE CASCADE]';

  -- ON DELETE CASCADE: room_amenity (через room)
  INSERT INTO room (code,capacity) VALUES ('R-c1',4);
  INSERT INTO room_amenity (room_id,amenity_id) SELECT r.room_id,a.amenity_id FROM room r,amenity a WHERE r.code='R-c1' AND a.name='проектор';
  DELETE FROM room WHERE code='R-c1';
  SELECT count(*) INTO v_cnt FROM room_amenity WHERE room_id NOT IN (SELECT room_id FROM room);
  IF v_cnt>0 THEN RAISE EXCEPTION 'FAIL ON DELETE CASCADE room_amenity: %', v_cnt; END IF;
  RAISE NOTICE 'OK [room_amenity ON DELETE CASCADE]';

  -- ON DELETE CASCADE: booking_event (через booking)
  INSERT INTO room (code,capacity) VALUES ('R-bk',4);
  INSERT INTO app_user (email,full_name) VALUES ('bk@x.com','Bk');
  WITH b AS (
    INSERT INTO booking (room_id,user_id,time_range)
    SELECT r.room_id,u.user_id,tstzrange('2031-01-01 10:00+00','2031-01-01 11:00+00','[)')
    FROM room r,app_user u WHERE r.code='R-bk' AND u.email='bk@x.com' RETURNING booking_id)
  INSERT INTO booking_event (booking_id,event_type) SELECT booking_id,'created' FROM b;
  DELETE FROM booking WHERE room_id=(SELECT room_id FROM room WHERE code='R-bk');
  SELECT count(*) INTO v_cnt FROM booking_event e
    WHERE e.booking_id NOT IN (SELECT booking_id FROM booking);
  IF v_cnt>0 THEN RAISE EXCEPTION 'FAIL ON DELETE CASCADE booking_event: %', v_cnt; END IF;
  RAISE NOTICE 'OK [booking_event ON DELETE CASCADE]';
  DELETE FROM room WHERE code='R-bk';
  DELETE FROM app_user WHERE email='bk@x.com';

  -- ON DELETE SET NULL: manager_id
  UPDATE app_user SET manager_id=(SELECT user_id FROM app_user WHERE email='b@example.com')
    WHERE email='a@example.com';
  DELETE FROM app_user WHERE email='b@example.com';
  SELECT manager_id INTO v_mgr FROM app_user WHERE email='a@example.com';
  IF v_mgr IS NOT NULL THEN RAISE EXCEPTION 'FAIL ON DELETE SET NULL: %', v_mgr; END IF;
  RAISE NOTICE 'OK [app_user.manager_id ON DELETE SET NULL]';

  RAISE NOTICE '==================================================';
  RAISE NOTICE 'Все тесты пройдены: PK, UNIQUE, CHECK, NOT NULL, FK, EXCLUDE, DEFAULT, ON DELETE';
  RAISE NOTICE '==================================================';
END $$;