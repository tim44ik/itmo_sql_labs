erDiagram
    APP_USER ||--o{ USER_PHONE : "имеет телефоны"
    APP_USER ||--o{ BOOKING : "создаёт"
    APP_USER }o--o| APP_USER : "руководитель"

    ROOM ||--o{ BOOKING : "бронируется"
    ROOM ||--o{ ROOM_AMENITY : "оснащено"
    AMENITY ||--o{ ROOM_AMENITY : "входит в"

    BOOKING ||--o{ BOOKING_EVENT : "имеет события"

    APP_USER {
        bigint user_id PK
        text email
        text full_name
        text role "guest | employee | admin"
        bigint manager_id FK
        timestamptz created_at
    }

    USER_PHONE {
        bigint user_id PK, FK
        text phone PK
    }

    ROOM {
        bigint room_id PK
        text code
        int capacity
        boolean is_active
    }

    AMENITY {
        bigint amenity_id PK
        text name
    }

    ROOM_AMENITY {
        bigint room_id PK, FK
        bigint amenity_id PK, FK
        int quantity
    }

    BOOKING {
        bigint booking_id PK
        bigint room_id FK
        bigint user_id FK
        tstzrange time_range
        text status "active | cancelled | completed | no_show"
        timestamptz created_at
    }

    BOOKING_EVENT {
        bigint event_id PK
        bigint booking_id FK "identifying"
        text event_type "created | cancelled | completed | no_show"
        jsonb payload
        timestamptz created_at
    }