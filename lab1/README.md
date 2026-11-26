## Выбор СУБД

### Сравнительная таблица

| Критерий | PostgreSQL | MySQL | SQL Server / Oracle |
|---|---|---|---|
| **Модель данных и JSONB** | Реляционная модель + нативный `JSONB` с бинарным хранением, индексами GIN и операторами `@>`, `?`, `jsonb_path_query`. Полноценная поддержка полуструктурированных данных в одной БД. | Реляционная модель + тип `JSON`. Хранение как текста, индексация только через генерируемые колонки и функциональные индексы. Операторы беднее, чем в PostgreSQL. | Реляционная модель + `JSON`/`XML`. В SQL Server — `JSON` как текст с функциями `JSON_VALUE`, `OPENJSON`. В Oracle — нативный `JSON` (21c+), но экосистема тяжелее и дороже. |
| **Транзакции и MVCC** | Полноценные ACID-транзакции, MVCC на уровне строк, уровни изоляции `READ COMMITTED`, `REPEATABLE READ`, `SERIALIZABLE`. `SERIALIZABLE` реализован через SSI (Serializable Snapshot Isolation). | InnoDB: ACID, MVCC, уровни `READ COMMITTED`, `REPEATABLE READ`, `SERIALIZABLE`. По умолчанию `REPEATABLE READ`, что отличается от PostgreSQL. | Полноценные ACID-транзакции, MVCC. В SQL Server — `READ COMMITTED SNAPSHOT`, `SNAPSHOT`, `SERIALIZABLE`. В Oracle — `READ COMMITTED`, `SERIALIZABLE`. |
| **Ограничения целостности (FK, CHECK, exclusion)** | FK, `CHECK`, `UNIQUE`, `NOT NULL`, **`EXCLUDE USING gist`** — декларативный запрет пересечения диапазонов. Partial и expression-индексы. | FK, `CHECK` (с 8.0.16), `UNIQUE`, `NOT NULL`. **Нет `EXCLUDE`-ограничений** — пересечение интервалов проверяется только триггером или в приложении. | FK, `CHECK`, `UNIQUE`. В SQL Server и Oracle **нет** аналога `EXCLUDE` в привычном виде: пересечения ловятся триггерами или `SERIALIZABLE`-транзакцией с повторной проверкой. |
| **RLS и безопасность** | Нативный `ROW LEVEL SECURITY`: `CREATE POLICY` + `ALTER TABLE ... ENABLE ROW LEVEL SECURITY`. Позволяет разграничить данные сотрудников и администратора на уровне БД. | RLS отсутствует. Разграничение — только через `GRANT` на таблицы/колонки или в приложении. | SQL Server: RLS есть (`CREATE SECURITY POLICY`). Oracle: VPD (Virtual Private Database). Функционально достаточно, но настройка тяжелее. |
| **Экосистема и инструменты** | `EXPLAIN (ANALYZE, BUFFERS)`, `pg_stat_statements`, `auto_explain`, `pg_stat_activity`, расширения (`pg_trgm`, `btree_gist`, `postgis`). Открытый код, активное сообщество. | `EXPLAIN ANALYZE`, `performance_schema`, `SHOW PROFILE` (устар.). Экосистема большая, но диагностика чуть беднее. | SQL Server: `Query Store`, `Execution Plans`, `DMV`. Oracle: `AWR`, `SQL Trace`, `TKPROF`. Мощные, но проприетарные и часто платные. |
| **Стоимость / облако** | Бесплатно (лицензия PostgreSQL). Managed-варианты у всех облаков: RDS, Cloud SQL, Azure Database, Yandex Managed, Supabase, Neon. | Бесплатно (GPL/Commercial dual). Managed-варианты везде. | SQL Server: бесплатная Express-редакция с лимитами; Standard/Enterprise — платно. Oracle: дорогие лицензии, бесплатный XE с ограничениями. Managed — дорого. |

### Вывод

Для проекта выбираем PostgreSQL. Ключевой аргумент — требование «на одно помещение не может быть двух активных броней с пересечением по времени» закрывается декларативно через `EXCLUDE USING gist (room_id WITH =, time_range WITH &&) WHERE (status = 'active')`, чего нет ни в MySQL, ни в SQL Server/Oracle без триггеров. Дополнительно нужны строгие `FK`/`CHECK` для целостности броней и пользователей, `JSONB` — для журнала событий в той же БД, `ROW LEVEL SECURITY` — для разграничения доступа сотрудника и администратора. PostgreSQL бесплатен, поднимается одной строкой в `docker-compose` и имеет всё нужное для диагностики (`EXPLAIN`, `pg_stat_statements`).

## SQL vs NoSQL

**Сценарий:** журнал событий броней. Каждая операция с бронью пишет в `booking_event` событие одного из типов: `created`, `cancelled`, `completed`, `no_show`. При этом меняется `booking.status`, у которого свой набор значений: `active`, `cancelled`, `completed`, `no_show`. Соответствие: событие `created` переводит бронь в `status = 'active'`, событие `cancelled` — в `status = 'cancelled'`, и т. д. Оба enum'а ограничены `CHECK` в `init.sql`.

**Реляционный вариант:** таблица `booking_event(event_id, booking_id, event_type, payload JSONB, created_at)` с FK на `booking`. Запросы: события по брони, события за период, JOIN с `booking` и `room` для отчёта по загрузке. Транзакции нужны, чтобы `UPDATE booking SET status = 'active'` (или другой статус) и `INSERT INTO booking_event` были атомарны — иначе получим бронь без записи в журнале или событие без актуального статуса. Схема жёсткая, целостность держит FK, а согласованность двух enum'ов — `CHECK`-ограничения.

**Документный вариант:** коллекция `booking_events`, документ содержит `booking_id`, `event_type`, снимок брони (`room_code`, `user_email`, `time_range`) и `payload`. Запросы по `booking_id` и дате идут без JOIN, но данные о брони и помещении дублируются, а согласованность `event_type` в журнале и `status` в основной коллекции `bookings` обеспечивает только приложение — два `CHECK` уже не работают вместе.

**Вывод:** выбираем PostgreSQL. Основные брони и журнал событий храним в одной БД, `payload` — в `JSONB`: получаем гибкость документа при сохранении FK, транзакций и отчётных JOIN. Пара `booking.status` / `booking_event.event_type` остаётся согласованной в одной транзакции: `UPDATE booking` + `INSERT booking_event` фиксируются вместе, оба `CHECK` проверяются на месте. Чистый document store был бы оправдан только при очень большом потоке логов и отказе от строгой целостности — в нашем проекте это не так.

## Окружение

### Файлы

- `.env.example` — шаблон переменных окружения (копируется в `.env`).
- `.gitignore` — исключает `.env`, `pgdata/`, дампы, IDE-каталоги.
- `docker-compose.yml` — PostgreSQL 16 + Adminer, healthcheck, авто-применение `init.sql`.
- `init.sql` — каркас схемы: `app_user`, `room`, `booking`, `booking_event`.

### Запуск

```bash
cp .env.example .env
docker compose up -d
docker compose ps          # ждём healthy у course_db
docker compose logs db     # проверяем, что init.sql применился
```


## Smoke-запросы и проверка 

результат запуска запросов 1-3

```
                                                       version                                                        
----------------------------------------------------------------------------------------------------------------------
 PostgreSQL 16.16 (Debian 16.16-1.pgdg13+1) on x86_64-pc-linux-gnu, compiled by gcc (Debian 14.2.0-19) 14.2.0, 64-bit
(1 row)

INSERT 0 2
INSERT 0 1
 room_id | code | capacity | is_active 
---------+------+----------+-----------
       6 | A101 |        4 | t
       7 | A102 |        6 | t
(2 rows)

 user_id |     email     | full_name |   role   |          created_at          
---------+---------------+-----------+----------+------------------------------
       5 | a@example.com | Alice     | employee | 2026-11-23 21:01:53.13538+00
(1 row)
```

результат запуска с 4 запросом без комментария

```
                                                       version                                                        
----------------------------------------------------------------------------------------------------------------------
 PostgreSQL 16.16 (Debian 16.16-1.pgdg13+1) on x86_64-pc-linux-gnu, compiled by gcc (Debian 14.2.0-19) 14.2.0, 64-bit
(1 row)

INSERT 0 2
INSERT 0 1
 room_id | code | capacity | is_active 
---------+------+----------+-----------
       6 | A101 |        4 | t
       7 | A102 |        6 | t
(2 rows)

 user_id |     email     | full_name |   role   |          created_at          
---------+---------------+-----------+----------+------------------------------
       5 | a@example.com | Alice     | employee | 2026-11-23 21:01:53.13538+00
(1 row)

ERROR:  null value in column "time_range" of relation "booking" violates not-null constraint
DETAIL:  Failing row contains (4, 999999, 999999, null, active, 2026-11-23 21:01:53.137493+00).
```

## Академическая честность

Использовал ИИ для составления сценариев в [requirements.md](docs/requirements.md), также для составления сравнительной таблицы и выбора между SQL и NoSQL.
