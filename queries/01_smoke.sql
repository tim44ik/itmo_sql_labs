-- 1. Версия
SELECT version();

-- 2. Вставка корректных данных
INSERT INTO room (code, capacity) VALUES ('A101', 4), ('A102', 6);
INSERT INTO app_user (email, full_name) VALUES ('a@example.com', 'Alice');

-- 3. Чтение
SELECT * FROM room;
SELECT * FROM app_user;

-- 4. Негативный тест FK: ожидается ошибка
-- Раскомментируйте и выполните отдельно:
INSERT INTO booking (room_id, user_id) VALUES (999999, 999999);
